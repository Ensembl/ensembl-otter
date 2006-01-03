
=pod

=head1 NAME - Bio::Otter::Lace::Blast

=head1 DESCRIPTION

    Similar to a Pipeline RunnableDB, but for Otter on the fly blast/est2genome

=cut


## BEGIN Block to avoid some hassle with pipeline configuration

BEGIN{
# or put %Config here and modify symbol table as below
#     *{"Bio::EnsEMBL::Pipeline::Config::General::Config"} = \%Config;
#     *{"Bio::EnsEMBL::Pipeline::Config::Blast::Config"} = \%Config;

    my @fake_modules = qw(
                          BlastableVersion.pm
                          Bio/EnsEMBL/Pipeline/Config/General.pm
                          Bio/EnsEMBL/Pipeline/Config/Blast.pm
                          );
    map { $INC{$_} = 1 } @fake_modules;
}

####
package Bio::EnsEMBL::Pipeline::Config::General;

use strict;

sub import {

    my ($callpack) = caller(0); # Name of the calling package
    my $pack = shift; # Need to move package off @_

    # had to put this inline here
    my %Config = (
                  
                  DATA_DIR => '/data/blastdb/Supported',
                  LIB_DIR  => '/usr/local/ensembl/lib',
                  ENS_DIR  => '/usr/local/ensembl/data',
                  
                  # location of output and error files
                  # (can also be specified on RuleManager command line)
                  PIPELINE_OUTPUT_DIR => '/out',
                  
                  # temporary working space (e.g. /tmp)
                  PIPELINE_WORK_DIR   => '/tmp',
                  
                  # default runner script
                  PIPELINE_RUNNER_SCRIPT => 'runner.pl',
                  
                  # automatic update in input_id_analysis of completed jobs
                  AUTO_JOB_UPDATE     => 1,
                  
                  PIPELINE_REPEAT_MASKING => ['RepeatMask','trf'],
                  
                  SOFT_MASKING => 0,
                  );
    if ($^O eq 'linux') {
        $Config{'BIN_DIR'} = '/nfs/disk100/humpub/LINUXbin';
    }
    elsif ($^O eq 'dec_osf') {
        $Config{'BIN_DIR'} = '/nfs/disk100/humpub/OSFbin';
    }
    else {
        my $bin_dir = '/usr/local/bin';
        warn "Guessing BIN_DIR is '$bin_dir' for operating system '$^O'";
        $Config{'BIN_DIR'} = $bin_dir;
    }

    # Get list of variables supplied, or else all
    my @vars = @_ ? @_ : keys(%Config);
    return unless @vars;

    # Predeclare global variables in calling package
    eval "package $callpack; use vars qw("
         . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	if (defined $Config{ $_ }) {
            no strict 'refs';
	    # Exporter does a similar job to the following
	    # statement, but for function names, not
	    # scalar variables:
	    *{"${callpack}::$_"} = \$Config{ $_ };
	} else {
	    die "Error: Config: $_ not known (See Bio::Otter::Lace::Blast)\n";
	}
    }
}

1;

package Bio::EnsEMBL::Pipeline::Config::Blast;

use strict;


sub import {

    my ($callpack) = caller(0); # Name of the calling package
    my $pack = shift; # Need to move package off @_

    # had to put this inline here.
    my %Config = (
                  DB_CONFIG => [{name =>'empty'}],
                  UNKNOWN_ERROR_STRING => 'WHAT',
                  );


    # Get list of variables supplied, or else all
    my @vars = @_ ? @_ : keys(%Config);
    return unless @vars;

    # Predeclare global variables in calling package
    eval "package $callpack; use vars qw("
         . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	    if (defined $Config{ $_ }) {
                no strict 'refs';
	        # Exporter does a similar job to the following
	        # statement, but for function names, not
	        # scalar variables:
	        *{"${callpack}::$_"} = \$Config{ $_ };
	    } else {
	        die "Error: Config: $_ not known (See Bio::Otter::Lace::Blast)\n";
	    }
    }
}

1;

package BlastableVersion;

#### Configurable variables

my $cache_file = '/var/tmp/blast_versions';
my $tracking_db = 'mysql:blastdb;cbi2.internal.sanger.ac.uk';
my $tracking_user = 'blastdbro';
my $tracking_pass = '';

#### No more configurable variables

use vars qw(%versions $debug $revision);

$debug = 0;
$revision='$Revision: 1.9 $ ';
$revision =~ s/\$.evision: (\S+).*/$1/;

#### CONSTRUCTORS

sub new {
    my $proto = shift;
    my $self = { };
    bless ($self, ref($proto) || $proto);
    return $self;
}

#### ACCESSOR METHODS

sub date { localtime; }
sub name { $0; }
sub version { 1.0.0; }
sub sanger_version { 1.0.0; }

#### PUBLIC METHODS

sub force_dbi { }
sub set_hostname { }
sub get_version { }
1;






##########################################################################
##########################################################################
##########################################################################

# START of Bio::Otter::Lace::Blast

##########################################################################
##########################################################################
##########################################################################

package Bio::Otter::Lace::Blast;

use strict;
use warnings;
use Bio::EnsEMBL::Pipeline::SeqFetcher::OBDAIndexSeqFetcher;
use Bio::EnsEMBL::Pipeline::Runnable::Finished_EST;
use Bio::EnsEMBL::Pipeline::Runnable::Finished_Blast;
use Bio::EnsEMBL::Pipeline::Config::General;
use Bio::Otter::Lace::PersistentFile;
use Bio::EnsEMBL::Root;
use File::Basename;
use File::Path 'rmtree';

our @ISA = qw(Bio::EnsEMBL::Root);

sub new{
    my( $pkg, @args ) = @_;
    my $self = bless {}, $pkg;
    my ($database, $pressdb, $indicate, $analysis, $i_parser)  = 
        $self->_rearrange([qw(DATABASE BLAST_IDX_PROG INDICATE ANALYSIS INDICATE_PARSER)],@args);

    # required!!!
    $self->analysis($analysis) || $self->throw("$self->new() needs an analysis obj");
    
    # use defaults
    $database ||= $analysis->db_file;
    $indicate ||= 'indicate';
    $pressdb  ||= 'pressdb';
    $i_parser ||= 'singleWordParser';

    # set the options
    $self->database($database) || $self->throw("$self->new() needs a database");
    $self->indicate_program($indicate);
    $self->blast_idx_program($pressdb);
    $self->indicate_parser($i_parser);

    return $self;
}

sub database{
    my ($self, $db) = @_;
    if($db){
        my @dbs = @{[split(/,/, $db)]};
        my $dirnames  = {};
        my $basenames = {};
        my $analysis  = $self->analysis();
        foreach my $file(@dbs){
            next unless -e $file;
            my $dirname             = dirname($file);
            my $basename            = basename($file);
            $dirnames->{$dirname}   = 1;
            $basenames->{$basename} = 1;
            $self->db_basenames($basename);
            $self->db_dirname($dirname);
            last;
        }
        warn "Only one db supported currently why not use `cat @dbs`" if scalar(@dbs) > 1;
        $self->throw("files must exist") unless scalar(keys(%$basenames));
        $self->throw("files must be in same directory " . join(" ", keys(%$dirnames)))
            if scalar(keys(%$dirnames)) > 1;
        # incase it wasn't set
        $analysis->db_file($dbs[0]);
        $analysis->db($self->indicate_index);
    }
    return $self->db_dirname() . "/" . $self->db_basenames();
}

sub db_basenames{
    my ($self, $basenames) = @_;
    # $self->{'_basenames'} = $basenames if ref($basenames) eq 'ARRAY';
    $self->{'_basenames'} = $basenames if $basenames;
    return $self->{'_basenames'};    
}
sub db_dirname{
    my ($self, $dirname) = @_;
    $self->{'_dirname'} = $dirname if $dirname;
    return $self->{'_dirname'};
}
sub hide_error{
    my ($self, $hide) = @_;
    $self->{'_hide_error'} = ($hide ? 1 : 0) if defined $hide;
    return $self->{'_hide_error'};
}

sub analysis{
    my ($self, $ana) = @_;
    $self->{'_analysis'} = $ana if $ana;
    return $self->{'_analysis'};
}

sub initialise{
    my ($self, $seq) = @_;
    my $fasta = $self->database();
    $self->query($seq) if $seq;

    # check for the file, & last modified 
    # the function returns true if file is newer i.e. needs reindexing
    if($self->_file_needs_indexing($fasta)){
        eval{
            $self->pressdb_fasta($fasta);
            $self->indicate_fasta($fasta);
        };
        if($@){
            warn "$@\n";
            $self->_remove_files($fasta);
            return 0;
        }
    }

    Bio::EnsEMBL::Pipeline::Runnable::Finished_Blast->add_regex($self->analysis->db_file, '(\S+)');

    return 1;
}

# returns true if fasta is newer
# false otherwise

sub _file_needs_indexing{
    my ($self, $fasta) = @_;
    my $ret = 0;

    # create the info file for the fasta file
    my $filestamp = Bio::Otter::Lace::PersistentFile->new();
    $filestamp->root($self->db_dirname());
    $filestamp->name('.efficient_indexing_'. $self->db_basenames());

    my ($fasta_mod) = (stat($fasta))[9];
    if(-e $filestamp->full_name){
        my $rfh = $filestamp->read_file_handle();
        my $saved_mod = <$rfh>;
        $ret = 1 unless $saved_mod == $fasta_mod;
    }else{
        # the info file doesn't exist it must be new
        $ret = 1;
    }
    if($ret){ # the file has changed need to update the info file
        my $wfh = $filestamp->write_file_handle();
        print $wfh $fasta_mod;
    }
    return $ret;
}
sub _remove_files{
    my ($self, $fasta) = @_;
    my $filestamp = Bio::Otter::Lace::PersistentFile->new();
    $filestamp->root($self->db_dirname());
    $filestamp->name('.efficient_indexing_'. $self->db_basenames());
    $filestamp->rm();
    rmtree($self->indicate_index());
}
sub add_output{
    my ($self, @out) = @_;
    
    if (@out) {
        my $name = $self->query->display_id;
        foreach my $fp (@out) {
            $fp->seqname($name);
        }
        push(@{$self->{'__output'}}, @out) if @out;
    }
    return undef;
}
sub output{
    my ($self) = @_;
    return $self->{'__output'} || [];
}
sub seqfetcher{
    my ($self, $fetcher) = @_;
    $self->{'_seqfetcher'} = $fetcher if $fetcher;
    return $self->{'_seqfetcher'};
}
sub run{
    my ($self) = @_;
    my $seq = $self->query();
    my $analysis = $self->analysis();

    my $runnable = Bio::EnsEMBL::Pipeline::Runnable::Finished_EST->new(
        -analysis => $self->analysis(),
        -query    => $seq->get_repeatmasked_seq($PIPELINE_REPEAT_MASKING),
        -unmasked => $seq,
        );
    $runnable->run();
    $self->seqfetcher($runnable->seqfetcher) unless $self->seqfetcher();
    $self->add_output($runnable->output());
    
}

sub run_on_selected_CloneSequences{
    my ($self, $ss, $slice_adaptor) = @_;
    my $sel = $ss->selected_CloneSequences_as_contig_list;
    local *OLDERR;
    if($self->hide_error){
        open(OLDERR, ">&STDERR") || print "Couldn't copy STDERR\n";
        open(STDERR, ">/dev/null")    || print "Couldn't reopen STDERR to /dev/null\n";
    }

    foreach my $cs(@$sel){
        my $first_ctg = $cs->[0];
        my $last_ctg = $cs->[$#$cs];
        
        my $chr = $first_ctg->chromosome->name;  
        my $chr_start = $first_ctg->chr_start;
        my $chr_end = $last_ctg->chr_end;
        
        warn "fetching slice $chr $chr_start $chr_end \n";
        my $slice = $slice_adaptor->fetch_by_chr_start_end($chr, $chr_start, $chr_end);
        
        ### Check we got a slice
        my $tp = $slice->get_tiling_path;
        if(@$tp){
            foreach my $tile(@$tp){
                my $seq = $tile->component_Seq();
                printf STDERR "Searching sequence '%s'\n", $seq->display_id;
                $self->query($seq);
                $self->run();
            }
        }else{
            warn "Didn't get slice\n";
        }
    }
    if($self->hide_error){
        close(STDERR)            || print "Couldn't close STDERR";
        open(STDERR, ">&OLDERR") || print "Couldn't restore STDERR";
        close(OLDERR);
    }
}

sub pressdb_fasta{
    my ($self, $fasta) = @_;
    my $pressdb = $self->blast_idx_program();
    (system($pressdb, 
            '-t', "'otterlace on-the-fly blast database'",
            $fasta
            ) == 0) || die "Can't pressdb";

}
sub indicate_fasta{
    my ($self, $fasta) = @_;

    my $indicate = $self->indicate_program();

    
    my $parser        = $self->indicate_parser();
    my $file_prefix   = $self->db_basenames();
    my $data_dir      = $self->db_dirname();
    my $index         = $self->indicate_index();

    my @indicate_call = ($indicate,
                         '--data_dir',    $data_dir,
                         '--file_prefix', $file_prefix,
                         '--index',       $index,
                         '--parser',      $parser,
                         );
    # @indicate_call = qw[/usr/local/ensembl/bin/indicate --data_dir ~/tmp --file_prefix subseq4roy.fa --index ~/tmp/local_search$$ --parser singleWordParser];
    (system(@indicate_call) == 0) || die "Can't do:\n\n@indicate_call\n";
    return 1;
}

sub indicate_index{
    my ($self, $index) = @_;
    if($index){
        $self->{'_indicate_index'} = $index;
    }elsif(!$self->{'_indicate_index'}){
        my $base = $self->db_basenames();
        $base =~ s/\.//g;
        my $idx = $self->db_dirname() . "/local_search_" . $base;
        $self->{'_indicate_index'} = $idx;
    }
    else{
        
    }
    return $self->{'_indicate_index'};
}

sub indicate_parser{
    my ($self, $parser) = @_;
    if($parser){
        $self->{'_indicate_parser'} = $parser;
    }
    return $self->{'_indicate_parser'};
}
sub indicate_program{
    my ($self, $ind) = @_;
    if($ind){
        $self->{'_indicate_program'} = $ind;
        if(my $add_to_path = dirname($ind)){
            $ENV{'PATH'} .= ":$add_to_path";
        }
    }
    return $self->{'_indicate_program'};
}
sub blast_idx_program{
    my ($self, $idx) = @_;
    if($idx){
        $self->{'_blast_idx_program'} = $idx;
    }
    return $self->{'_blast_idx_program'};
}
sub query{
    my ($self, $seq) = @_;
    
    if ($seq) {
        $self->{'_query_seq'} = $seq;
    }
    return $self->{'_query_seq'};
}
sub lib_path{
    my ($self, $path) = @_;
    if($path){
        $self->{'_lib_path'} = $path;
        $ENV{'LD_LIBRARY_PATH'} .= ":$path";
    }
    return $self->{'_lib_path'};
}

1;

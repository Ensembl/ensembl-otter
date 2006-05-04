
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
        warn "Guessing BIN_DIR is '$bin_dir' for operating system '$^O'\n";
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
        if (defined $Config{$_}) {
            no strict 'refs';

            # Exporter does a similar job to the following
            # statement, but for function names, not
            # scalar variables:
            *{"${callpack}::$_"} = \$Config{$_};
        }
        else {
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
$revision='$Revision: 1.11 $ ';
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
use Carp;
use File::Basename;
use File::Path 'rmtree';

use Bio::EnsEMBL::Pipeline::Analysis;
use Bio::EnsEMBL::Pipeline::SeqFetcher::OBDAIndexSeqFetcher;
use Bio::EnsEMBL::Pipeline::Runnable::Finished_EST;
use Bio::EnsEMBL::Pipeline::Runnable::Finished_Blast;
use Bio::EnsEMBL::Pipeline::Config::General;

use Bio::Otter::Lace::PersistentFile;

use Bio::EnsEMBL::Ace::Filter::Cigar_ace_parser;

sub new{
    my( $pkg ) = @_;
    return bless {}, $pkg;
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

sub initialise {
    my ($self) = @_;

    # Get all the configuration options
    my $cl = $self->AceDatabase->Client();
    foreach my $attribute (qw{
        database
        homol_tag
        method_tag
        method_color
        logic_name
        indicate
        indicate_parser
        blast_indexer
        right_priority
      })
    {
        my $value = $cl->option_from_array([ 'local_blast', $attribute ]);
        $self->$attribute($value);
    }
    
    my $fasta_file = $self->database or return;
    unless (-e $fasta_file) {
        confess "Fasta file '$fasta_file' defined config does not exist";
    }
    
    # Make the analysis object needed by the Runnable
    my $ana_obj = Bio::EnsEMBL::Pipeline::Analysis->new(
        -LOGIC_NAME    => $self->logic_name,
        -INPUT_ID_TYPE => 'CONTIG',
        -PARAMETERS    =>
          'cpus=1 E=1e-4 B=100000 Z=500000000 -hitdist=40 -wordmask=seg',
        -PROGRAM     => 'wublastn',
        -GFF_SOURCE  => 'Est2Genome',
        -GFF_FEATURE => 'similarity',
        -DB_FILE     => $fasta_file,
    );
    $self->analysis($ana_obj);

    # check for the file, & last modified
    # the function returns true if file is newer i.e. needs reindexing
    if ($self->_file_needs_indexing($fasta_file)) {
        eval {
            $self->pressdb_fasta($fasta_file);
            $self->indicate_fasta($fasta_file);
        };
        if ($@) {
            $self->_remove_files($fasta_file);
            confess "Error creating indice for '$fasta_file' :\n", $@;
        }
    }

    Bio::EnsEMBL::Pipeline::Runnable::Finished_Blast->add_regex($fasta_file, '(\S+)');
}

# Attribute methods


sub AceDatabase {
    my( $self, $AceDatabase ) = @_;
    
    if ($AceDatabase) {
        $self->{'_AceDatabase'} = $AceDatabase;
    }
    return $self->{'_AceDatabase'};
}

sub database {
    my ($self, $db) = @_;
    if ($db) {
        my @dbs       = @{ [ split(/,/, $db) ] };
        my $dirnames  = {};
        my $basenames = {};
        my $analysis  = $self->analysis();
        foreach my $file (@dbs) {
            next unless -e $file;
            my $dirname  = dirname($file);
            my $basename = basename($file);
            $dirnames->{$dirname}   = 1;
            $basenames->{$basename} = 1;
            $self->db_basenames($basename);
            $self->db_dirname($dirname);
            last;
        }
        warn "Only one db supported currently why not use `cat @dbs`"
          if scalar(@dbs) > 1;
        confess("files must exist") unless scalar(keys(%$basenames));
        confess(
            "files must be in same directory " . join(" ", keys(%$dirnames)))
          if scalar(keys(%$dirnames)) > 1;

        # incase it wasn't set
        $analysis->db_file($dbs[0]);
        $analysis->db($self->indicate_index);
    }
    return $self->db_dirname() . "/" . $self->db_basenames();
}

sub homol_tag {
    my( $self, $homol_tag ) = @_;
    
    if ($homol_tag) {
        $self->{'_homol_tag'} = $homol_tag;
    }
    return $self->{'_homol_tag'} || 'DNA_homol';
}

sub method_tag {
    my( $self, $method_tag ) = @_;
    
    if ($method_tag) {
        $self->{'_method_tag'} = $method_tag;
    }
    return $self->{'_method_tag'} || substr(sprintf('blast*%s*', $self->database), 0, 39);
}

sub method_color {
    my( $self, $method_color ) = @_;
    
    if ($method_color) {
        $self->{'_method_color'} = $method_color;
    }
    return $self->{'_method_color'} || 'ORANGE';
}

sub logic_name {
    my( $self, $logic_name ) = @_;
    
    if ($logic_name) {
        $self->{'_logic_name'} = $logic_name;
    }
    return $self->{'_logic_name'} || sprintf('blast*%s*', $self->database);
}

sub indicate {
    my ($self, $ind) = @_;
    if ($ind) {
        $self->{'_indicate_program'} = $ind;
        if (my $add_to_path = dirname($ind)) {
            $ENV{'PATH'} .= ":$add_to_path";
        }
    }
    return $self->{'_indicate_program'} || 'indicate';
}

sub indicate_parser {
    my( $self, $indicate_parser ) = @_;
    
    if ($indicate_parser) {
        $self->{'_indicate_parser'} = $indicate_parser;
    }
    return $self->{'_indicate_parser'} || 'singleWordParser';
}

sub blast_indexer {
    my( $self, $blast_indexer ) = @_;
    
    if ($blast_indexer) {
        $self->{'_blast_indexer'} = $blast_indexer;
    }
    return $self->{'_blast_indexer'} || 'pressdb';
}

sub right_priority {
    my( $self, $right_priority ) = @_;
    
    if ($right_priority) {
        $self->{'_right_priority'} = $right_priority;
    }
    # Right_priority of 0.2 is what EGAG needed, so
    # I have used it as the hard coded default.
    return $self->{'_right_priority'} || 0.2;
}


sub ace_Method_string {
    my ($self) = @_;

    my $tag = $self->method_tag;
    my $col = $self->method_colour;
    my $pri = $self->right_priority;
    
    my $meth_ace = <<END_OF_METHOD;

Method : "$tag"
Colour   $col
Gapped
Score_by_width
Score_bounds     70 130
Width 2.0
Right_priority $pri
Max_mag  4000.000000
Blixem_N

END_OF_METHOD

     return $meth_ace;
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

sub run {
    my( $self ) = @_;
    
    my $ace = '';
    foreach my $name ($self->list_GenomeSequence_names) {
        my ($masked, $unmasked) = $self->get_masked_unmasked_seq($ace, $name);
        my $sf = $self->run_blast($masked, $unmasked);
        $ace .= $self->format_ace_output($name, $sf);
    }
    $ace .= $self->ace_Method_string if $ace;
    return $ace;
}

sub run_blast {
    my ($self, $masked, $unmasked) = @_;

    my $analysis = $self->analysis();

    my $runnable = Bio::EnsEMBL::Pipeline::Runnable::Finished_EST->new(
        -analysis => $self->analysis(),
        -query    => $masked,
        -unmasked => $unmasked,
        );
    $runnable->run();
    $self->seqfetcher($runnable->seqfetcher) unless $self->seqfetcher();
    return $runnable->output;
}

sub format_ace_output {
    my ($self, $contig_name, $fp_list) = @_;

    unless (@$fp_list) {
        warn "No hits found on '$contig_name'\n";
        return '';
    }

    my $is_protein = 0;
    my $homol_tag    = $self->homol_tag;
    my $homol_method = $self->homol_method;

    my $ace = qq{\nSequence : "$contig_name"\n};
    foreach my $fp (@$fp_list) {
        # est2genome has strand info from splice sites which we are losing
        # contig_strand is always 1 at the moment
        # align_coords() will break if we fix this
        my $strand = ($fp->strand || 1) * $fp->hstrand;

        # Transforms the gapped alignment information in the cigar string
        # into a series of Align blocks for acedb's Smap system. This
        # enables gapped alignments to be displayed in blixem.
        my ($seq_coord, $target_coord, $other) = Bio::EnsEMBL::Ace::Filter::Cigar_ace_parser::align_coords(
            $fp->cigar, $fp->start, $fp->end, $fp->hstart, $strand, $is_protein);

        # In acedb strand is encoded by start being greater
        # than end if the feature is on the negative strand.
        my $start = $fp->start;
        my $end   = $fp->end;
        if ($strand == -1){
            ($start, $end) = ($end, $start);
        }

        # The first part of the line is all we need if there are no
        # gaps in the alignment between genomic sequence and hit.
        my $query_line = sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d},
          $homol_tag, $fp->hseqname, $homol_method, $fp->percent_id,
          $fp->start, $fp->end, $fp->hstart, $fp->hend;


        if (@$seq_coord > 1) {
            # Gapped alignments need two or more Align blocks to describe
            # them. The information at the start of the line is needed for
            # each block so that they all end up under the same tag once
            # they are parsed into acedb.
            for (my $i = 0; $i < @$seq_coord; $i++){
                $ace .=  $query_line . " Align $seq_coord->[$i] $target_coord->[$i] $other->[$i]\n";
            }
        } else {
            $ace .= $query_line . "\n";
        }
    }
    
    return $ace;
}

sub list_GenomeSequence_names {
    my ($self) = @_;
    
    return map $_->name, $self->AceDatabase->aceperl_db_handle->fetch(GenomeSequence => '*');
}

sub get_masked_unmasked_seq {
    my ($self, $name) = @_;
    
    my $ace = $self->AceDatabase->aceperl_db_handle;
    my $dna_obj = $ace->fetch(DNA => $name)
        or confess "Failed to get DNA object '$name' from acedb database";
    my $dna_str = $dna_obj->fetch->at->name;
    warn "Got DNA string ", length($dna_str), " long";

    my $unmasked = Bio::Seq->new(
        -id         => $name,
        -seq        => $dna_str,
        -alphabet   => 'dna',
        );

    $ace->raw_query("find Sequence $name");

    # Mask DNA with trf features
    my $feat_list = $ace->raw_query('show -a Feature');
    my $feat_txt = Hum::Ace::AceText->new($feat_list);
    foreach my $f ($feat_txt->get_values('Feature."?trf')) {
        my ($start, $end) = @$f;
        if ($start > $end) {
            ($start, $end) = ($end, $start);
        }
        my $length = $end - $start + 1;
        substr($dna_str, $start - 1, $length) = 'n' x $length;
    }
    
    # Mask DNA with RepeatMakser features
    my $repeat_list = $ace->raw_query('show -a Motif_homol');
    my $repeat_txt = Hum::Ace::AceText->new($repeat_list);
    foreach my $m ($repeat_txt->get_values('Motif_homol')) {
        my ($start, $end) = @$m[3,4];
        if ($start > $end) {
            ($start, $end) = ($end, $start);
        }
        my $length = $end - $start + 1;
        substr($dna_str, $start - 1, $length) = 'n' x $length;
    }
    
    my $masked = Bio::Seq->new(
        -id         => $name,
        -seq        => $dna_str,
        -alphabet   => 'dna',
        );
    
    return ($masked, $unmasked);
}


sub pressdb_fasta{
    my ($self, $fasta) = @_;
    my $pressdb = $self->blast_indexer();
    (system($pressdb, 
            '-t', "'otterlace on-the-fly blast database'",
            $fasta
            ) == 0) || confess "Can't pressdb";

}
sub indicate_fasta{
    my ($self, $fasta) = @_;

    my $indicate = $self->indicate();

    
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
    #warn "indexing command: @indicate_call\n";
    # @indicate_call = qw[/usr/local/ensembl/bin/indicate --data_dir ~/tmp --file_prefix subseq4roy.fa --index ~/tmp/local_search$$ --parser singleWordParser];
    (system(@indicate_call) == 0) || confess "Can't do:\n\n@indicate_call\n";
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
    return $self->{'_indicate_index'};
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

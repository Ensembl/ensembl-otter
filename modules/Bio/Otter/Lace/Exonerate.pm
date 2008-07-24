
=pod

=head1 NAME - Bio::Otter::Lace::Exonerate

=head1 DESCRIPTION

    Similar to a Pipeline RunnableDB, but for Otter on the fly Exonerate

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

                  DATA_DIR => '/data/blastdb/Finished',
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

                  PIPELINE_REPEAT_MASKING => ['RepeatMasker','trf'],

                  SOFT_MASKING => 0,
                  );
    if ($^O eq 'linux') {
        $Config{'BIN_DIR'} = '/usr/local/ensembl/bin';
    }
    elsif ($^O eq 'dec_osf') {
        $Config{'BIN_DIR'} = '/usr/local/ensembl/bin';
    }
    else {
        my $bin_dir = '/usr/local/ensembl/bin';
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
$revision='$Revision: 1.6 $ ';
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

# START of Bio::Otter::Lace::Exonerate

##########################################################################
##########################################################################
##########################################################################

package Bio::Otter::Lace::Exonerate;

use strict;
use warnings;
use Carp;
use File::Basename;
use File::Path 'rmtree';

use Bio::DB::Flat::OBDAIndex;

use Bio::EnsEMBL::Pipeline::Analysis;
use Bio::EnsEMBL::Pipeline::Runnable::Finished_Exonerate;
use Bio::EnsEMBL::Pipeline::Config::General;


use Bio::Seq;
use Hum::Ace::AceText;
use Hum::Ace::Method;
use Bio::Otter::Lace::PersistentFile;

use Bio::EnsEMBL::Ace::Filter::Cigar_ace_parser;

sub new{
    my( $pkg ) = @_;
    return bless {}, $pkg;
}

sub initialise {
    my ($self) = @_;

    my $cl = $self->AceDatabase->Client();

    # Just return if a blast database hasn't been defined
    my $fasta_file = $cl->option_from_array([ 'local_exonerate', 'database' ]);
    return unless $fasta_file;

    unless ($fasta_file =~ m{^/}) {
        confess "fasta file '$fasta_file' is not an absolute path";
    }

    $self->database($fasta_file);
    unless (-e $fasta_file) {
        confess "Fasta file '$fasta_file' defined in config does not exist";
    }
    warn "Found exonerate database: '$fasta_file'\n";


    # Get all the other configuration options
    foreach my $attribute (qw{
        homol_tag
        method_tag
        method_color
        logic_name
        query_type
      })
    {
        my $value = $cl->option_from_array([ 'local_exonerate', $attribute ]);
        $self->$attribute($value);
    }

    # Make the analysis object needed by the Runnable
    my $ana_obj = Bio::EnsEMBL::Pipeline::Analysis->new(
        -LOGIC_NAME    => $self->logic_name,
        -INPUT_ID_TYPE => 'CONTIG',
        -PARAMETERS    => '',
        -PROGRAM     => '/software/anacode/bin/exonerate',
        -GFF_SOURCE  => 'exonerate',
        -GFF_FEATURE => 'similarity',
        -DB_FILE     => $fasta_file,
    );
    $self->analysis($ana_obj);

}

# Attribute methods


sub AceDatabase {
    my( $self, $AceDatabase ) = @_;

    if ($AceDatabase) {
        $self->{'_AceDatabase'} = $AceDatabase;
    }
    return $self->{'_AceDatabase'};
}

sub analysis {
    my( $self, $analysis ) = @_;

    if ($analysis) {
        $self->{'_analysis'} = $analysis;
    }
    return $self->{'_analysis'};
}

sub query_type {
    my( $self, $query_type ) = @_;

    if ($query_type) {
    	my $type = lc($query_type);
    	$type =~ s/\s//g;
	    unless( $type eq 'dna' || $type eq 'protein' ){
	      confess "not the right query type: $type";
	    }
        $self->{'_query_type'} = $type;
    }
    return $self->{'_query_type'};
}

sub database {
    my( $self, $database ) = @_;

    if ($database) {
        $self->{'_database'} = $database;
    }
    return $self->{'_database'};
}

sub db_basename {
    my ($self) = @_;

    return basename($self->database);
}

sub db_dirname{
    my ($self) = @_;

    return dirname($self->database);
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
    if (my $tag = $self->{'_method_tag'}) {
        return $tag;
    } elsif ($self->db_basename =~ /(.{1,40})$/) {
        return $1;
    } else {
        return;
    }
}

sub method_color {
    my( $self, $method_color ) = @_;

    if ($method_color) {
        $self->{'_method_color'} = $method_color;
    }
    return $self->{'_method_color'} || 'GREEN';
}

sub logic_name {
    my( $self, $logic_name ) = @_;

    if ($logic_name) {
        $self->{'_logic_name'} = $logic_name;
    }
    return $self->{'_logic_name'} || $self->db_basename;
}


sub sequence_fetcher {
    my( $self, $sequence_fetcher ) = @_;

    if ($sequence_fetcher) {
        $self->{'_sequence_fetcher'} = $sequence_fetcher;
    }
    return $self->{'_sequence_fetcher'};
}

sub ace_Method {
    my ($self) = @_;

    my $method = $self->{'_ace_method'};
    unless ($method) {
        $method = $self->{'_ace_method'} = Hum::Ace::Method->new;
        $method->name(  $self->method_tag   );
        $method->color( $self->method_color );

        # This will put the results next to the annotated genes
        $method->zone_number(2);

        $method->gapped(1);
        $method->blixem_type('N');
        $method->width(2.0);
        $method->score_method('width');
        $method->score_bounds(70, 130);
        $method->max_mag(4000);
    }
    return $method;
}


sub _remove_files {
    my ($self, $fasta) = @_;
    my $filestamp = Bio::Otter::Lace::PersistentFile->new();
    $filestamp->root($self->db_dirname());
    $filestamp->name('.efficient_indexing_'. $self->db_basename());
    $filestamp->rm();
    rmtree($self->indicate_index());
}

sub run {
    my( $self ) = @_;

    my $ace = '';
    foreach my $name ($self->list_GenomeSequence_names) {
        warn "Genomic query sequence: '$name'\n";
        my ($masked, $smasked, $unmasked) = $self->get_masked_unmasked_seq($name);

        unless ($masked->seq =~ /[acgtACGT]{5}/) {
            warn "Sequence '$name' is entirely repeat\n";
            next;
        }

        my $features = $self->run_exonerate($masked, $smasked, $unmasked);
        $ace .= $self->format_ace_output($name, $features);
    }
    if ($ace) {
        my $fetcher = $self->sequence_fetcher;
        my $names = $self->delete_all_hit_names;
        foreach my $hit_name (@$names) {
            my $seq = $fetcher->get_Seq_by_acc($hit_name)
                or confess "Failed to fetch '$hit_name' by Acc using a '", ref($fetcher), "'";
            if($self->query_type eq 'dna') {
            	$ace .= $self->ace_DNA($hit_name, $seq);
            } else {
            	$ace .= $self->ace_PEPTIDE($hit_name, $seq);
        	}
    	}
    }
    return $ace;
}

sub ace_DNA {
    my ($self, $name, $seq) = @_;

    my $ace = qq{\nSequence "$name"\n\nDNA "$name"\n};

    my $dna_string = $seq->seq;
    while ($dna_string =~ /(.{1,60})/g) {
        $ace .= $1 . "\n";
    }
    return $ace;
}

sub ace_PEPTIDE {
    my ($self, $name, $seq) = @_;

    my $ace = qq{\nSequence "$name"\n\nPEPTIDE "$name"\n};

    my $dna_string = $seq->seq;
    while ($dna_string =~ /(.{1,60})/g) {
        $ace .= $1 . "\n";
    }
    return $ace;
}

sub run_exonerate {
    my ($self, $masked, $smasked, $unmasked) = @_;

    my $analysis = $self->analysis();
    my $exo_options = $self->query_type() eq 'protein' ?
    	'-m p2g --forcescan q --softmasktarget yes -M 1500  --score 150' :
    	'-m e2g --forcescan q --softmasktarget yes  -M 1500 --dnahspthreshold 120 -s 2000 --geneseed 300' ;

    my $runnable = Bio::EnsEMBL::Pipeline::Runnable::Finished_Exonerate->new(
        -analysis => $self->analysis(),
        -target    => $smasked,
        -query_db	=> 	$self->database(),
        -query_type => $self->query_type() || 'dna',
        -exo_options => $exo_options
        );
    $runnable->run();
    $self->sequence_fetcher($runnable->seqfetcher);
    return [$runnable->output];
}

sub add_hit_name {
    my( $self, $name ) = @_;

    $self->{'_hit_names'}{$name} = 1;
}

sub delete_all_hit_names {
    my ($self) = @_;

    my $hit_names = [ sort keys %{$self->{'_hit_names'}} ];
    $self->{'_hit_names'} = undef;
    return $hit_names;
}

sub format_ace_output {
    my ($self, $contig_name, $fp_list) = @_;

    unless (@$fp_list) {
        warn "No hits found on '$contig_name'\n";
        return '';
    }

    my $is_protein = $self->query_type eq 'protein';
    my $homol_tag   = $self->homol_tag;
    my $method_tag  = $self->method_tag;

    my %name_fp_list;
    foreach my $fp (@$fp_list) {
        my $hname = $fp->hseqname;
        my $list = $name_fp_list{$hname} ||= [];
        push @$list, $fp;
    }

    my $ace = '';
    foreach my $hname (sort keys %name_fp_list) {
        # Save hit name. This is used to get the DNA sequence for
        # each hit from the fasta file using the OBDA index.
        $self->add_hit_name($hname);

        $ace       .= qq{\nSequence : "$contig_name"\n};
        my $hit_ace = qq{\nSequence : "$hname"\n};

        foreach my $fp (@{ $name_fp_list{$hname} }) {

            # est2genome has strand info from splice sites, which we are losing.
            # contig_strand is always 1 at the moment
            # align_coords() will break if we fix this
            my $strand = ($fp->hstrand || 1) * $fp->strand;

            # Transforms the gapped alignment information in the cigar string
            # into a series of Align blocks for acedb's Smap system. This
            # enables gapped alignments to be displayed in blixem.
            my ($seq_coord, $target_coord, $other) = Bio::EnsEMBL::Ace::Filter::Cigar_ace_parser::align_coords(
                $fp->cigar_string, $fp->start, $fp->end, $fp->hstart, $strand, $is_protein);

            # In acedb strand is encoded by start being greater
            # than end if the feature is on the negative strand.
            my $start = $fp->start;
            my $end   = $fp->end;

            if ($strand == -1){
                ($start, $end) = ($end, $start);
            }

            # Show coords in hit back to genomic sequence. (The annotators like this.)
            $hit_ace .= sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d\n},
              $homol_tag, $contig_name, $method_tag, $fp->percent_id,
              $fp->hstart, $fp->hend, $start, $end;

            # The first part of the line is all we need if there are no
            # gaps in the alignment between genomic sequence and hit.
            my $query_line = sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d},
              $homol_tag, $hname, $method_tag, $fp->percent_id,
              $start, $end, $fp->hstart, $fp->hend;

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

        $ace .= $hit_ace;
    }

    return $ace;
}

sub list_GenomeSequence_names {
    my ($self) = @_;

    my $ace_dbh = $self->AceDatabase->aceperl_db_handle;
    return map $_->name, $ace_dbh->fetch(Genome_Sequence => '*');
}

sub get_masked_unmasked_seq {
    my ($self, $name) = @_;

    my $ace = $self->AceDatabase->aceperl_db_handle;
    my ($dna_obj) = $ace->fetch(DNA => $name)
        or confess "Failed to get DNA object '$name' from acedb database";
    my $dna_str = $dna_obj->fetch->at->name;
    my $sm_dna_str = uc $dna_str;

    warn "Got DNA string ", length($dna_str), " long";

    my $unmasked = Bio::Seq->new(
        -id         => $name,
        -seq        => $dna_str,
        -alphabet   => 'dna',
        );

    $ace->raw_query("find Sequence $name");

    # Mask DNA with trf features
    my $feat_list = $ace->raw_query('show -a Feature');
    #warn "Features: $feat_list";
    my $feat_txt = Hum::Ace::AceText->new($feat_list);
    foreach my $f ($feat_txt->get_values('Feature."?trf')) {
        my ($start, $end) = @$f;
        if ($start > $end) {
            ($start, $end) = ($end, $start);
        }
        my $length = $end - $start + 1;
        substr($dna_str, $start - 1, $length) = 'n' x $length;
        substr($sm_dna_str, $start - 1, $length) = lc substr($sm_dna_str, $start - 1, $length);
    }

    # Mask DNA with RepeatMakser features
    my $repeat_list = $ace->raw_query('show -a Motif_homol');
    #warn "Repeats: $repeat_list";
    my $repeat_txt = Hum::Ace::AceText->new($repeat_list);
    foreach my $m ($repeat_txt->get_values('Motif_homol')) {
        my ($start, $end) = @$m[3,4];
        if ($start > $end) {
            ($start, $end) = ($end, $start);
        }
        my $length = $end - $start + 1;
        substr($dna_str, $start - 1, $length) = 'n' x $length;
        substr($sm_dna_str, $start - 1, $length) = lc substr($sm_dna_str, $start - 1, $length);
    }

    my $masked = Bio::Seq->new(
        -id         => $name,
        -seq        => $dna_str,
        -alphabet   => 'dna',
        );
    my $softmasked = Bio::Seq->new(
        -id         => $name,
        -seq        => $sm_dna_str,
        -alphabet   => 'dna',
        );

    return ($masked,$softmasked,$unmasked);
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

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


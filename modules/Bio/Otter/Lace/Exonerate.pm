
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
                          Bio/EnsEMBL/Analysis/Config/General.pm
                          Bio/EnsEMBL/Analysis/Config/Blast.pm
                          );
    map { $INC{$_} = 1 } @fake_modules;
}

####
package Bio::EnsEMBL::Analysis::Config::General;

use strict;

sub import {

    my ($callpack) = caller(0); # Name of the calling package
    my $pack = shift; # Need to move package off @_

    # had to put this inline here
    my %Config = (

                  DATA_DIR => '/data/blastdb/Finished',
                  LIB_DIR  => '/software/anacode/lib',
                  BIN_DIR  => '/software/anacode/bin',


                  # temporary working space (e.g. /tmp)
                  ANALYSIS_WORK_DIR => '/tmp',

                  ANALYSIS_REPEAT_MASKING => ['RepeatMasker','trf'],

                  SOFT_MASKING => 0,
                  );

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

package Bio::EnsEMBL::Analysis::Config::Blast;

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
$revision='$Revision: 1.48 $ ';
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


use Bio::Seq;
use Hum::Ace::AceText;
use Hum::Ace::Method;
use Hum::FastaFileIO;
use Bio::Otter::Lace::PersistentFile;
use Bio::EnsEMBL::Analysis::Runnable::Finished::Exonerate;
use Bio::EnsEMBL::Ace::Filter::Cigar_ace_parser;

sub new{
    my( $pkg ) = @_;
    return bless {}, $pkg;
}

sub initialise {
    my ($self,$fasta_file) = @_;

    my $cl = $self->AceDatabase->Client();

    if(!$fasta_file) {
    	# Just return if a blast database hasn't been defined
    	$fasta_file = $cl->option_from_array([ 'local_exonerate', 'database' ]);
    	return unless $fasta_file;
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
    }

    unless ($fasta_file =~ m{^/}) {
        confess "fasta file '$fasta_file' is not an absolute path";
    }

    $self->database($fasta_file);
    unless (-e $fasta_file) {
        confess "Fasta file '$fasta_file' defined in config does not exist";
    }
    warn "Found exonerate database: '$fasta_file'\n";

    #$self->homol_tag(($self->query_type eq 'protein') ? 'Pep_homol' : 'DNA_homol');
	$self->homol_tag('DNA_homol');

    # Make the analysis object needed by the Runnable
    my $ana_obj = Bio::EnsEMBL::Analysis->new(
        -LOGIC_NAME    => $self->logic_name,
        -INPUT_ID_TYPE => 'CONTIG',
        -PARAMETERS    => '',
        -PROGRAM     => 'exonerate',
        -GFF_SOURCE  => 'exonerate',
        -GFF_FEATURE => 'similarity',
        -DB_FILE     => $fasta_file,
    );
    $self->analysis($ana_obj);

}

sub write_seq_file {
	my ($self) = @_;
	my $query_file   = "/tmp/query_seq.$$.fa";
	# Write out the query sequence
	my $seq = $self->query_seq();
	if(@$seq) {
		my $query_out = Hum::FastaFileIO->new("> $query_file");
    	$query_out->write_sequences(@$seq);
	    $query_out = undef;

	    return $query_file;
	}

	return;
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

sub genomic_seq {
    my( $self, $genomic_seq ) = @_;

    if ($genomic_seq) {
        $self->{'_genomic_seq'} = $genomic_seq;
    }
    return $self->{'_genomic_seq'};
}

sub genomic_start {
	my ( $self, $genomic_start ) = @_;
	if ( defined $genomic_start ) {
		$self->{'_genomic_start'} = $genomic_start;
	}
	return $self->{'_genomic_start'};
}

sub genomic_end {
	my ( $self, $genomic_end ) = @_;
	if ( defined $genomic_end ) {
		$self->{'_genomic_end'} = $genomic_end;
	}
	return $self->{'_genomic_end'};
}

sub query_seq {
    my( $self, $seq ) = @_;

    if ($seq) {
        $self->{'_query_seq'} = $seq;
    }
    return $self->{'_query_seq'};
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

    return $self->{'_query_type'} || 'dna';
}

sub acedb_homol_tag {
    my( $self, $tag ) = @_;

    if ($tag) {
        $self->{'_acedb_homol_tag'} = $tag;
    }

    return $self->{'_acedb_homol_tag'};
}

sub database {
    my( $self, $database ) = @_;

    if ($database) {
        $self->{'_database'} = $database;
    }
    return $self->{'_database'};
}

sub score {
	my ( $self, $score ) = @_;
	if ($score) {
		$self->{'_score'} = $score;
	}
	return $self->{'_score'};
}

sub bestn {
	my ( $self, $bestn) = @_;
	if ($bestn) {
		$self->{'_bestn'} = $bestn;
	}
	return $self->{'_bestn'};
}

sub max_intron_length {
    my ( $self, $max_intron_length) = @_;
    if ($max_intron_length) {
        $self->{'_max_intron_length'} = $max_intron_length;
    }
    return $self->{'_max_intron_length'};
}

sub dnahsp {
	my ( $self, $dnahsp ) = @_;
	if ($dnahsp) {
		$self->{'_dnahsp'} = $dnahsp;
	}
	return $self->{'_dnahsp'};
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

	my $method = $self->{'_ace_method'} = Hum::Ace::Method->new;
	$method->name(  $self->method_tag   );

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
    my $name = $self->genomic_seq->name;
    my ($masked, $smasked, $unmasked) = $self->get_masked_unmasked_seq;

	# only run exonerate with the specified subsequence of the genomic sequence

	map { $_->seq($_->subseq($self->genomic_start, $self->genomic_end)) } ($masked, $smasked, $unmasked);

	unless ($masked->seq =~ /[acgtACGT]{5}/) {
        warn "The genomic sequence is entirely repeat\n";
        return $ace;
    }

    my $features = $self->run_exonerate($masked, $smasked, $unmasked);
    $self->append_polyA_tail($features) unless $self->query_type eq 'protein' ;

    $ace .= $self->format_ace_output($name, $features);

    return $ace;
}

# Extend the last or first align feature to incorporate
# the query sequence PolyA/T tail if any

sub append_polyA_tail {
	my( $self, $features ) = @_;
	my %by_hit_name;
	my $debug = 0;

	# Group the DnaDnaAlignFeatures by hit_name
	map { $by_hit_name{$_->hseqname} ||= [] ; push @{$by_hit_name{$_->hseqname}}, $_ } @$features;

	HITNAME: for my $hit_name (keys %by_hit_name) {
		my ($sub_seq,$alt_exon,$match,$cigar,$pattern);
		my $hit_features = $by_hit_name{$hit_name};
		my $hit_strand = $hit_features->[0]->hstrand;
		print STDOUT "PolyA/T tail Search for $hit_name...\n";
		print STDOUT "Processing $hit_name with ".scalar(@$hit_features)." Features\n" if $debug;
		# fetch the hit sequence
		my $fetcher = $self->sequence_fetcher;
		my $seq = $fetcher->{$hit_name};
		# Get the AlignFeature that needs to be extended
		# last exon if hit in forward strand, first if in reverse

		@$hit_features = sort {					$hit_strand == -1 ?
								$a->hstart <=> $b->hstart || $b->hend <=> $a->hend :
								$b->hend <=> $a->hend || $a->hstart <=> $b->hstart		} @$hit_features;
		$alt_exon = shift @$hit_features;
		print STDOUT ($hit_strand == -1 ? "Reverse" : "Forward").
			" strand: start ".$alt_exon->hstart." end ".$alt_exon->hend." length ".$seq->sequence_length."\n" if $debug;
		if($hit_strand == -1) {
			next HITNAME unless $alt_exon->hstart > 1;
			$sub_seq = $seq->sub_sequence(1,($alt_exon->hstart-1));
			print STDOUT "subseq <1-".($alt_exon->hstart-1)."> is\n$sub_seq\n" if $debug;
			$pattern = '^(.*T{3,})$';  # <AGAGTTTTTTTTTTTTTTTTTTTTTT>ALT_EXON_START
		} else {
			next HITNAME unless $alt_exon->hend < $seq->sequence_length;
			$sub_seq = $seq->sub_sequence(($alt_exon->hend+1),$seq->sequence_length);
			print STDOUT "subseq <".($alt_exon->hend+1)."-".$seq->sequence_length."> is\n$sub_seq\n" if $debug;
			$pattern = '^(A{3,}.*)$';  # ALT_EXON_END<AAAAAAAAAAAAAAAAAAAAAAAACGAG>
		}

		if($sub_seq =~ /$pattern/i ) {
			$match = length $1;
			$cigar = $alt_exon->cigar_string;
			print STDOUT "Found $match bp long polyA/T tail\n";

			# change the feature cigar string
			if(not $cigar =~ s/(\d*)M$/($1+$match)."M"/e ) {
				$cigar = $cigar."${match}M";
			}
			print STDOUT "old cigar $cigar new $cigar\n" if $debug;
			$alt_exon->cigar_string($cigar);

			# change the feature coordinates
			if($hit_strand == -1) {
				$alt_exon->hstart($alt_exon->hstart-$match);
			} else {
				$alt_exon->hend($alt_exon->hend+$match);
			}

			if($alt_exon->strand == 1) {
				$alt_exon->end($alt_exon->end+$match);
			} else {
				$alt_exon->start($alt_exon->start-$match);
			}

		} else {
			next HITNAME;
		}
	}
}

sub run_exonerate {
    my ($self, $masked, $smasked, $unmasked) = @_;

    my $analysis = $self->analysis();
    my $score = $self->score() || ( $self->query_type() eq 'protein' ? 150 : 2000 );
    my $dnahsp = $self->dnahsp || 120 ;
    my $bestn = $self->bestn || 0;
    my $max_intron_length = $self->max_intron_length || 200000;
    
    my $exo_options = "--softmasktarget yes -M 500 --bestn $bestn --maxintron $max_intron_length --score $score";
    
    $exo_options .= $self->query_type() eq 'protein' ?
    	" -m p2g" :
    	" -m e2g --softmaskquery yes --dnahspthreshold $dnahsp --geneseed 300" ;

    my $runnable = Bio::EnsEMBL::Analysis::Runnable::Finished::Exonerate->new(
        -analysis => $self->analysis(),
        -target    => $smasked,
        -query_db	=> 	$self->database(),
        -query_type => $self->query_type() || 'dna',
        -exo_options => $exo_options,
        -program => $self->analysis->program
        );
    $runnable->run();

    return $runnable->output;
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

	my $offset = $self->genomic_start - 1;

    my %name_fp_list;
    foreach my $fp (@$fp_list) {
        my $hname = $fp->hseqname;
        my $list = $name_fp_list{$hname} ||= [];
        push @$list, $fp;
        $fp->start($fp->start + $offset);
        $fp->end($fp->end + $offset);
    }

    my $ace = '';
    foreach my $hname (sort keys %name_fp_list) {
        # Save hit name. This is used to get the DNA sequence for
        # each hit from the fasta file using the OBDA index.
        $self->add_hit_name($hname);

		my $prefix = $is_protein ? 'Protein' : 'Sequence';

        $ace       .= qq{\nSequence : "$contig_name"\n};
        my $hit_ace = qq{\n$prefix : "$hname"\n};

        foreach my $fp (@{ $name_fp_list{$hname} }) {

            # est2genome has strand info from splice sites, which we are losing.
            # contig_strand is always 1 at the moment
            # align_coords() will break if we fix this
            my $strand = $fp->strand;

            # Transforms the gapped alignment information in the cigar string
            # into a series of Align blocks for acedb's Smap system. This
            # enables gapped alignments to be displayed in blixem.
            my ($seq_coord, $target_coord, $other) = Bio::EnsEMBL::Ace::Filter::Cigar_ace_parser::align_coords(
                $fp->cigar_string, $fp->start, $fp->end, $fp->hstart, $fp->hend, $strand, $fp->hstrand, $is_protein);


            #print STDOUT "Parse ".join(" ",$fp->cigar_string, $fp->start, $fp->end, $fp->hstart, $fp->hend, $strand, $fp->hstrand, $is_protein)."\n";

            # In acedb strand is encoded by start being greater
            # than end if the feature is on the negative strand.
            my $start = $fp->start;
            my $end   = $fp->end;
            my $hstart = $fp->hstart;
            my $hend 	= $fp->hend;

			if($fp->hstrand ==-1){
            	$fp->hstrand(1);
            	$strand *= -1;
            }

            if ($strand == -1){
                ($start, $end) = ($end, $start);
            }

			my $hit_homol_tag = 'DNA_homol';

            # Show coords in hit back to genomic sequence. (The annotators like this.)
            $hit_ace .= sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d\n},
              $hit_homol_tag, $contig_name, $method_tag, $fp->percent_id,
              $hstart, $hend, $start, $end;
              #print STDOUT sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d\n},
              #$homol_tag, $contig_name, $method_tag, $fp->percent_id,
              #$fp->hstart, $fp->hend, $start, $end;

            # The first part of the line is all we need if there are no
            # gaps in the alignment between genomic sequence and hit.
            my $query_line = sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d},
              $self->acedb_homol_tag, $hname, $method_tag, $fp->percent_id,
              $start, $end, $hstart, $hend;

            if (@$seq_coord > 1) {
                # Gapped alignments need two or more Align blocks to describe
                # them. The information at the start of the line is needed for
                # each block so that they all end up under the same tag once
                # they are parsed into acedb.
                for (my $i = 0; $i < @$seq_coord; $i++){
                    $ace .=  $query_line . ($is_protein ? " AlignDNAPep" : " Align") . " $seq_coord->[$i] $target_coord->[$i] $other->[$i]\n";
                    #print STDOUT $query_line . " Align $seq_coord->[$i] $target_coord->[$i] $other->[$i]\n";
                }
            } else {
                $ace .= $query_line . "\n";
                #print STDOUT $query_line ."\n";
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
    my ($self) = @_;

	my $ace = $self->AceDatabase->aceperl_db_handle;
    my $name = $self->genomic_seq->name;
    my $dna_str = $self->genomic_seq->sequence_string;
    $dna_str =~ s/-/N/g;
    my $sm_dna_str = uc $dna_str;

    warn "Got DNA string ", length($dna_str), " long";

    my $unmasked = Bio::Seq->new(
        -id         => $name,
        -seq        => $dna_str,
        -alphabet   => 'dna',
        );

    $ace->raw_query("find Sequence $name");

	# Make sure trf and repeatmasker are loaded before masking
	my $DataFactory = $self->AceDatabase->pipeline_DataFactory();
	my $filters = $DataFactory->get_names2filters();

	foreach (keys %$filters) { $filters->{$_}->wanted(0);}
	my ($rm,$trf) = ('RepeatMasker','trf');
	my $load;
	for ($rm,$trf) {
		if(!$filters->{$_}->done) {
			$filters->{$_}->wanted(1);
			$load = 1;
		}
	}
	$self->AceDatabase->topup_pipeline_data_into_ace_server() if $load;
	foreach (keys %$filters) { $filters->{$_}->wanted(1); }

	# must reset the sequence in the current list
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

Anacode B<email> anacode@sanger.ac.uk


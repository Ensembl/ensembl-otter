
=pod

=head1 NAME - Bio::Otter::Lace::Exonerate

=head1 DESCRIPTION

    Similar to a Pipeline RunnableDB, but for Otter on the fly Exonerate

=cut

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

	return undef;
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
    $method->color( $self->method_color );
    $method->show_up_strand(1);

    # This will put the results next to the annotated genes
    $method->zone_number(2);

    $method->gapped(0);
    $method->join_aligns(0);
    $method->blixem_type( ($self->query_type eq 'dna') ? 'N' : 'P');
    $method->width(2.0);
    $method->score_method('width');
    $method->score_bounds(70, 130);
    $method->max_mag(4000);

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

    unless ($masked->seq =~ /[acgtACGT]{5}/) {
        warn "The genomic sequence is entirely repeat\n";
        return $ace;
    }

    my $features = $self->run_exonerate($masked, $smasked, $unmasked);
    $self->append_polyA_tail($features) unless $self->query_type eq 'protein' ;

    $ace .= $self->format_ace_output($name, $features);

    if ($ace) {
        my $fetcher = $self->sequence_fetcher;
        my $names = $self->delete_all_hit_names;
        foreach my $hit_name (@$names) {
            my $seq = $fetcher->get_Seq_by_acc($hit_name)
                or confess "Failed to fetch '$hit_name' by Acc using a '", ref($fetcher), "'";
            if($self->query_type eq 'protein') {
            	$ace .= $self->ace_PEPTIDE($hit_name, $seq);
            } else {
            	$ace .= $self->ace_DNA($hit_name, $seq);
        	}
    	}
    }
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
		my $seq = $fetcher->get_Seq_by_acc($hit_name)
                or confess "Failed to fetch '$hit_name' by Acc using a '", ref($fetcher), "'";
		# Get the AlignFeature that needs to be extended
		# last exon if hit in forward strand, first if in reverse

		@$hit_features = sort {					$hit_strand == -1 ?
								$a->hstart <=> $b->hstart || $b->hend <=> $a->hend :
								$b->hend <=> $a->hend || $a->hstart <=> $b->hstart		} @$hit_features;
		$alt_exon = shift @$hit_features;
		print STDOUT ($hit_strand == -1 ? "Reverse" : "Forward").
			" strand: start ".$alt_exon->hstart." end ".$alt_exon->hend." length ".$seq->length."\n" if $debug;
		if($hit_strand == -1) {
			next HITNAME unless $alt_exon->hstart > 1;
			$sub_seq = $seq->subseq(1,($alt_exon->hstart-1));
			print STDOUT "subseq <1-".($alt_exon->hstart-1)."> is\n$sub_seq\n" if $debug;
			$pattern = '^(.*T{3,})$';  # <AGAGTTTTTTTTTTTTTTTTTTTTTT>ALT_EXON_START
		} else {
			next HITNAME unless $alt_exon->hend < $seq->length;
			$sub_seq = $seq->subseq(($alt_exon->hend+1),$seq->length);
			print STDOUT "subseq <".($alt_exon->hend+1)."-".$seq->length."> is\n$sub_seq\n" if $debug;
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

    my $ace = qq{\nProtein "$name"\n\nPEPTIDE "$name"\n};

    my $prot_string = $seq->seq;
    while ($prot_string =~ /(.{1,60})/g) {
        $ace .= $1 . "\n";
    }
    return $ace;
}

sub run_exonerate {
    my ($self, $masked, $smasked, $unmasked) = @_;

    my $analysis = $self->analysis();
    my $score = $self->score() || ( $self->query_type() eq 'protein' ? 150 : 2000 );
    my $dnahsp = $self->dnahsp || 120 ;
    my $bestn = $self->bestn || 0;
    my $exo_options = $self->query_type() eq 'protein' ?
    	"-m p2g --softmasktarget yes -M 500 --score $score --bestn $bestn" :
    	"-m e2g --softmasktarget yes --softmaskquery yes -M 500 --dnahspthreshold $dnahsp -s $score --bestn $bestn --geneseed 300" ;

    my $runnable = Bio::EnsEMBL::Analyis::Runnable::Finished::Exonerate->new(
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
              $fp->hstart, $fp->hend, $start, $end;
              #print STDOUT sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d\n},
              #$homol_tag, $contig_name, $method_tag, $fp->percent_id,
              #$fp->hstart, $fp->hend, $start, $end;

            # The first part of the line is all we need if there are no
            # gaps in the alignment between genomic sequence and hit.
            my $query_line = sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d},
              $self->acedb_homol_tag, $hname, $method_tag, $fp->percent_id,
              $start, $end, $fp->hstart, $fp->hend;

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

	foreach (keys %$filters) { $filters->{$_}->wanted(0); }
	my ($rm,$trf) = ('repeatmasker','trf');
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


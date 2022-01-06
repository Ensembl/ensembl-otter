=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 NAME - OtterTest::Exonerate

=head1 DESCRIPTION

The package formerly known as Bio::Otter::Lace::Exonerate.
Similar to a Pipeline RunnableDB, but for Otter on the fly Exonerate.

=cut

package OtterTest::Exonerate;

use strict;
use warnings;

use File::Basename;
use File::Temp 'tempfile';
use Bio::Otter::Log::Log4perl 'logger';

# pipeline configuration
# this must come before Bio::EnsEMBL::Analysis::Runnable::Finished::Exonerate
use OtterTest::Exonerate::Config::General;
use OtterTest::Exonerate::Config::Blast;

use Test::Requires qw( Bio::EnsEMBL::Analysis::Tools::BlastDBTracking );
use Bio::EnsEMBL::Analysis::Tools::BlastDBTracking;
{
    ## no critic (Subroutines::ProtectPrivateSubs)
    Bio::EnsEMBL::Analysis::Tools::BlastDBTracking->_Fake_version_for_otf(1);
}

use Bio::Otter::Utils::FeatureSort qw( feature_sort );

use Bio::Seq;
use Hum::Ace::Method;
use Hum::FastaFileIO;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Analysis::Runnable::Finished::Exonerate;

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub initialise {
    my ($self, $fasta_file) = @_;

    unless ($fasta_file =~ m{^/}) {
        $self->logger->logconfess("fasta file '$fasta_file' is not an absolute path");
    }

    $self->database($fasta_file);
    unless (-e $fasta_file) {
        $self->logger->logconfess("Fasta file '$fasta_file' defined in config does not exist");
    }
    $self->logger->info("Found exonerate database: '$fasta_file'");

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

    return;
}

sub write_seq_file {
    my ($self) = @_;

    # Write out the query sequence
    my $seq = $self->query_seq();
    if(@$seq) {
        my ($query_fh, $query_file) = tempfile
          ('query_seq.XXXXXX', SUFFIX => '.fa', TMPDIR => 1, UNLINK => 1);

        my $query_out = Hum::FastaFileIO->new($query_fh); # accepts GLOB type fh
        $query_out->write_sequences(@$seq);
        $query_out = undef;

        return $query_file;
    }

    return;
}

# Attribute methods


sub AceDatabase {
    my ($self, $AceDatabase) = @_;

    if ($AceDatabase) {
        $self->{'_AceDatabase'} = $AceDatabase;
    }
    return $self->{'_AceDatabase'};
}

sub analysis {
    my ($self, $analysis) = @_;

    if ($analysis) {
        $self->{'_analysis'} = $analysis;
    }
    return $self->{'_analysis'};
}

sub genomic_seq {
    my ($self, $genomic_seq) = @_;

    if ($genomic_seq) {
        $self->{'_genomic_seq'} = $genomic_seq;
    }
    return $self->{'_genomic_seq'};
}

sub genomic_start {
    my ($self, $genomic_start) = @_;
    if ( defined $genomic_start ) {
        $self->{'_genomic_start'} = $genomic_start;
    }
    return $self->{'_genomic_start'};
}

sub genomic_end {
    my ($self, $genomic_end) = @_;
    if ( defined $genomic_end ) {
        $self->{'_genomic_end'} = $genomic_end;
    }
    return $self->{'_genomic_end'};
}

sub mask_target {
    my ($self, $mask_target) = @_;
    if ( defined $mask_target ) {
        $self->{'_mask_target'} = $mask_target;
    }
    return $self->{'_mask_target'};
}

sub query_seq {
    my ($self, $seq) = @_;

    if ($seq) {
        $self->{'_query_seq'} = $seq;
    }
    return $self->{'_query_seq'};
}

sub query_type {
    my ($self, $query_type) = @_;

    if ($query_type) {
        my $type = lc($query_type);
        $type =~ s/\s//g;
        unless( $type eq 'dna' || $type eq 'protein' ){
            $self->logger->logconfess("not the right query type: $type");
        }
        $self->{'_query_type'} = $type;
    }

    return $self->{'_query_type'} || 'dna';
}

sub acedb_homol_tag {
    my ($self, $tag) = @_;

    if ($tag) {
        $self->{'_acedb_homol_tag'} = $tag;
    }

    return $self->{'_acedb_homol_tag'};
}

sub database {
    my ($self, $database) = @_;

    if ($database) {
        $self->{'_database'} = $database;
    }
    return $self->{'_database'};
}

sub score {
    my ($self, $score) = @_;
    if ($score) {
        $self->{'_score'} = $score;
    }
    return $self->{'_score'};
}

sub bestn {
    my ($self, $bestn) = @_;
    if ($bestn) {
        $self->{'_bestn'} = $bestn;
    }
    return $self->{'_bestn'};
}

sub max_intron_length {
    my ($self, $max_intron_length) = @_;
    if ($max_intron_length) {
        $self->{'_max_intron_length'} = $max_intron_length;
    }
    return $self->{'_max_intron_length'};
}

sub dnahsp {
    my ($self, $dnahsp) = @_;
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
    my ($self, $homol_tag) = @_;

    if ($homol_tag) {
        $self->{'_homol_tag'} = $homol_tag;
    }
    return $self->{'_homol_tag'} || 'DNA_homol';
}

sub method_tag {
    my ($self, $method_tag) = @_;

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
    my ($self, $method_color) = @_;

    if ($method_color) {
        $self->{'_method_color'} = $method_color;
    }
    return $self->{'_method_color'} || 'GREEN';
}

sub logic_name {
    my ($self, $logic_name) = @_;

    if ($logic_name) {
        $self->{'_logic_name'} = $logic_name;
    }
    return $self->{'_logic_name'} || $self->db_basename;
}


sub sequence_fetcher {
    my ($self, $sequence_fetcher) = @_;

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


sub run {
    my ($self) = @_;

    my $ace = '';
    my $name = $self->genomic_seq->name;
    my $dna_str = $self->genomic_seq->sequence_string;
    $dna_str =~ s/-/N/g;

    my $sm_dna_str = $self->get_softmasked_dna($dna_str);

    my $unmasked = Bio::Seq->new(
        -id         => $name,
        -seq        => $dna_str,
        -alphabet   => 'dna',
        );

    my $smasked = Bio::Seq->new(
        -id         => $name,
        -seq        => $sm_dna_str,
        -alphabet   => 'dna',
        );

    # only run exonerate with the specified subsequence of the genomic sequence
    my $start = $self->genomic_start;
    my $end = $self->genomic_end;
    $_->seq($_->subseq($start, $end)) foreach $smasked, $unmasked;

    unless ($smasked->seq =~ /[ACGT]{5}/) {
        $self->logger->warn("The genomic sequence is entirely repeat");
        return $ace;
    }

    my $features = $self->run_exonerate($smasked, $unmasked);
    $self->append_polyA_tail($features) unless $self->query_type eq 'protein' ;

    $ace .= $self->format_ace_output($name, $features);

    return $ace;
}

# Extend the last or first align feature to incorporate
# the query sequence PolyA/T tail if any

sub append_polyA_tail {
    my ($self, $features) = @_;

    # Group the DnaDnaAlignFeatures by hit_name
    my %by_hit_name;
    push @{$by_hit_name{$_->hseqname} ||= []}, $_ for @$features;

    while (my ($hit_name, $hit_features) = each %by_hit_name) {
        $self->logger->info("PolyA/T tail Search for $hit_name...");
        $self->logger->debug("Processing $hit_name with ", scalar(@$hit_features), " Features\n");
        # fetch the hit sequence
        my $seq = $self->sequence_fetcher->{$hit_name};
        $self->append_polyA_tail_from_features($seq, $hit_features);
    }

    return;
}

sub append_polyA_tail_from_features {
    my ($self, $seq, $hit_features) = @_;

    my ($sub_seq,$alt_exon,$match,$cigar,$pattern);
    my $hit_strand = $hit_features->[0]->hstrand;

    # Get the AlignFeature that needs to be extended
    # last exon if hit in forward strand, first if in reverse

    @$hit_features = sort {
        $hit_strand == -1 ?
            $a->hstart <=> $b->hstart || $b->hend <=> $a->hend :
            $b->hend <=> $a->hend || $a->hstart <=> $b->hstart;
    } @$hit_features;
    $alt_exon = shift @$hit_features;
    $self->logger->debug(($hit_strand == -1 ? "Reverse" : "Forward"), " strand:",
                         " start ",  $alt_exon->hstart,
                         " end ",    $alt_exon->hend, 
                         " length ", $seq->sequence_length,
        );
    if($hit_strand == -1) {
        return unless $alt_exon->hstart > 1;
        $sub_seq = $seq->sub_sequence(1,($alt_exon->hstart-1));
        $self->logger->debug("subseq <1-", ($alt_exon->hstart-1), "> is\n$sub_seq\n");
        $pattern = '^(.*T{3,})$';  # <AGAGTTTTTTTTTTTTTTTTTTTTTT>ALT_EXON_START
    }
    else {
        return unless $alt_exon->hend < $seq->sequence_length;
        $sub_seq = $seq->sub_sequence(($alt_exon->hend+1),$seq->sequence_length);
        $self->logger->debug("subseq <", ($alt_exon->hend+1), "-", $seq->sequence_length, "> is\n$sub_seq\n");
        $pattern = '^(A{3,}.*)$';  # ALT_EXON_END<AAAAAAAAAAAAAAAAAAAAAAAACGAG>
    }

    if($sub_seq =~ /$pattern/i ) {
        $match = length $1;
        $cigar = $alt_exon->cigar_string;
        $self->logger->info("Found $match bp long polyA/T tail");

        # change the feature cigar string
        if(not $cigar =~ s/(\d*)M$/($1+$match)."M"/e ) {
            $cigar = $cigar."${match}M";
        }
        $self->logger->debug("old cigar $cigar new $cigar");
        $alt_exon->cigar_string($cigar);

        # change the feature coordinates
        if($hit_strand == -1) {
            $alt_exon->hstart($alt_exon->hstart-$match);
        }
        else {
            $alt_exon->hend($alt_exon->hend+$match);
        }

        if($alt_exon->strand == 1) {
            $alt_exon->end($alt_exon->end+$match);
        }
        else {
            $alt_exon->start($alt_exon->start-$match);
        }

    }

    return;
}

sub run_exonerate {
    my ($self, $smasked, $unmasked) = @_;

    my $analysis = $self->analysis();
    my $score = $self->score() || ( $self->query_type() eq 'protein' ? 150 : 2000 );
    my $dnahsp = $self->dnahsp || 120 ;
    my $bestn = $self->bestn || 0;
    my $max_intron_length = $self->max_intron_length || 200000;
    my $mask_target = $self->mask_target || 'soft';

    my $exo_options = "-M 500 --bestn $bestn --maxintron $max_intron_length --score $score";

    my $target;
    if ($mask_target eq 'soft') {
        $target = $smasked;
        $exo_options .= " --softmasktarget yes";
    } elsif ($mask_target eq 'none') {
        $target = $unmasked;
    } else {
        $self->logger->logcroak("mask_target type '$mask_target' not supported");
    }

    $exo_options .=
        $self->query_type() eq 'protein' ?
        " -m p2g" :
        " -m e2g --softmaskquery yes --dnahspthreshold $dnahsp --geneseed 300" ;

    my $runnable = Bio::EnsEMBL::Analysis::Runnable::Finished::Exonerate->new(
        -analysis    => $self->analysis(),
        -target      => $target,
        -query_db    => $self->database(),
        -query_type  => $self->query_type() || 'dna',
        -exo_options => $exo_options,
        -program     => $self->analysis->program
        );
    $runnable->run();

    return $runnable->output;
}

sub add_hit_name {
    my ($self, $name) = @_;

    $self->{'_hit_names'}{$name} = 1;

    return;
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
        $self->logger->warn("No hits found on '$contig_name'");
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
        my $hit_length = $self->sequence_fetcher->{$hname}->sequence_length;
        my $hit_ace = qq{\n$prefix : "$hname"\nLength $hit_length\n};

        foreach my $fp (feature_sort @{ $name_fp_list{$hname} }) {

            # In acedb strand is encoded by start being greater
            # than end if the feature is on the negative strand.
            my $strand  = $fp->strand;
            my $start   = $fp->start;
            my $end     = $fp->end;
            my $hstart  = $fp->hstart;
            my $hend    = $fp->hend;
            my $hstrand = $fp->hstrand;

            if ($hstrand ==-1){
                $self->logger->debug('Hit on reverse strand: swapping strands for ', $hname);
                $fp->reverse_complement;
                $hstrand = $fp->hstrand;
                $strand  = $fp->strand;
            }

            if ($strand == -1){
                ($start, $end) = ($end, $start);
            }

            my $hit_homol_tag = 'DNA_homol';

            # Show coords in hit back to genomic sequence. (The annotators like this.)
            $hit_ace .=
                sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d\n},
                $hit_homol_tag, $contig_name, $method_tag, $fp->percent_id,
                $hstart, $hend, $start, $end;
            # $self->logger->info(sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d\n},
            #                     $homol_tag, $contig_name, $method_tag, $fp->percent_id,
            #                     $fp->hstart, $fp->hend, $start, $end);

            # The first part of the line is all we need if there are no
            # gaps in the alignment between genomic sequence and hit.
            my $query_line =
                sprintf qq{Homol %s "%s" "%s" %.3f %d %d %d %d},
                $self->acedb_homol_tag, $hname, $method_tag, $fp->percent_id,
                $start, $end, $hstart, $hend;

            my @ugfs = $fp->ungapped_features;
            if (@ugfs > 1) {
                # Gapped alignments need two or more Align blocks to describe
                # them. The information at the start of the line is needed for
                # each block so that they all end up under the same tag once
                # they are parsed into acedb.
                foreach my $ugf (@ugfs){
                    my $ref_coord   = $strand  == -1 ? $ugf->end  : $ugf->start;
                    my $match_coord = $hstrand == -1 ? $ugf->hend : $ugf->hstart;
                    my $length      = ($ugf->hend - $ugf->hstart) + 1;
                    $ace .=
                        $query_line
                        . ($is_protein ? " AlignDNAPep" : " Align")
                        . " $ref_coord $match_coord $length\n";
                }
            } else {
                $ace .= $query_line . "\n";
            }
        }

        $ace .= $hit_ace;
    }

    return $ace;
}

sub get_softmasked_dna {
    my ($self, $dna_str) = @_;

    my $sm_dna_str = uc $dna_str;

    my $offset = $self->AceDatabase->offset;
    my $mask_sub = sub {

        chomp;
        return if /^\#\#/; # skip GFF headers

        # feature parameters
        my ( $start, $end ) = (split /\t/)[3,4];
        $start -= $offset;
        $end   -= $offset;

        # sanity checks
        $self->logger->logconfess("missing feature start in '$_'") unless defined $start;
        $self->logger->logconfess("non-numeric feature start: $start")
            unless $start =~ /^[[:digit:]]+$/;
        $self->logger->logconfess("missing feature end in '$_'") unless defined $end;
        $self->logger->logconfess("non-numeric feature end: $end")
            unless $end =~ /^[[:digit:]]+$/;

        if ($start > $end) {
            ($start, $end) = ($end, $start);
        }

        # mask against this feature
        my $length = $end - $start + 1;
        substr($sm_dna_str, $start - 1, $length,
               lc substr($sm_dna_str, $start - 1, $length));
    };

    # mask the sequences with repeat features
    my $dataset = $self->AceDatabase->DataSet;
    foreach my $filter_name (qw( trf RepeatMasker )) {
        my $filter = $dataset->filter_by_name($filter_name);
        $self->logger->logconfess("no filter named '${filter_name}'") unless $filter;
        $filter->call_with_session_data_handle(
            $self->AceDatabase,
            sub {
                my ($data_h) = @_;
                while (<$data_h>) { $mask_sub->(); }
            });
    }

    return $sm_dna_str;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


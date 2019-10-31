=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

package Bio::Vega::Gene;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument  qw ( rearrange );
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::EnsEMBL::Attribute;
use Bio::Vega::Utils::Attribute    qw ( get_first_Attribute_value get_name_Attribute_value );
use Bio::Vega::Utils::AttributesMixin;
use base 'Bio::EnsEMBL::Gene';


sub new {
  my ($class, @args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($gene_author, $status)  = rearrange([qw(AUTHOR STATUS)],@args);
  $self->gene_author($gene_author);
  $self->status($status) if ($status);
  return $self;
}

sub new_dissociated_copy {
    my ($self) = @_;

    my $pkg = ref($self);
    my $copy = $pkg->new_fast(+{
        map { $_ => $self->{$_} } (
            'analysis',     # ok to share object?
            'biotype',
            # 'canonical_transcript',    # not used by otter
            # 'canonical_transcript_id', # --"--
            'created_date',
            'description',
            'display_xref', # ok to share object?
            'end',
            'external_db',
            'external_name',
            'external_status',
            'gene_author',
            'is_current',
            'modified_date',
            'slice',        # ok to share object?
            'source',
            'stable_id',
            'start',
            'status',
            'strand',
            'truncated_flag',
            'version',
        )
                               });

    foreach my $ts ( @{$self->get_all_Transcripts} ) {
        $copy->add_Transcript($ts->new_dissociated_copy);
    }

    foreach my $at ( @{$self->get_all_Attributes} ) {
        my $at_pkg = ref($at);
        $copy->add_Attributes($at_pkg->new_fast({%$at}));
    }

    return $copy;
}

sub gene_author {
  my ($self, $value) = @_;
  if( defined $value) {
      if ($value->isa("Bio::Vega::Author")) {
          $self->{'gene_author'} = $value;
      } else {
          throw("Argument to gene_author must be a Bio::Vega::Author object.  Currently is [$value]");
      }
  }
  return $self->{'gene_author'};
}

sub source  {
  my ($self, @args) = @_;

  $self->{'source'} = shift @args if( @args );
  return ( $self->{'source'} || "havana" );
}

sub vega_hashkey {
    my ($self) = @_;

    my $seq_region_name = $self->seq_region_name
        || throw(  'seq_region_name must be set to generate vega_hashkey');
    my $start           = $self->seq_region_start
        || throw( 'seq_region_start must be set to generate vega_hashkey');
    my $end             = $self->seq_region_end 
        || throw(   'seq_region_end must be set to generate vega_hashkey');
    my $strand          = $self->seq_region_strand
        || throw('seq_region_strand must be set to generate vega_hashkey');
    my $biotype         = $self->biotype        
        || throw(          'biotype must be set to generate vega_hashkey');
    my $status          = $self->status         
        || throw(           'status must be set to generate vega_hashkey');
    my $source          = $self->source         
        || throw(           'source must be set to generate vega_hashkey');

    my $tran_count = scalar @{$self->get_all_Transcripts}
        || throw("there are no transcripts for this gene to generate correct vega_hashkey");

    my $description = $self->description || '';
    my $attrib_string = $self->Bio::Vega::Utils::AttributesMixin::all_Attributes_string;

    return join '-'
        , $seq_region_name, $start, $end, $strand
        , $biotype, $status, $source, $description, $tran_count, $attrib_string
        ;
}

sub vega_hashkey_structure {
    return join '-', qw(
        seq_region_name
        seq_region_start
        seq_region_end
        seq_region_strand
        biotype
        status
        source
        description
        transcript_count
        all_attrib_string
        );
}

sub vega_hashkey_sub {

  my ($self) = @_;
  my $vega_hashkey_sub={};
  my $trans=$self->get_all_Transcripts;
  foreach my $tran (@$trans){
      $vega_hashkey_sub->{$tran->stable_id}='transcript-stable-id';
  }
  return $vega_hashkey_sub;

}


=head2 truncated_flag

Either TRUE or FALSE (1 or 0), it flags whether
the gene contains all its components that are
stored in the database, and hence whether it is
editable in the client.  Defaults to 0.

=cut

sub truncated_flag {
  my ($self, $flag) = @_;
  if (defined $flag) {
      $self->{'truncated_flag'} = $flag ? 1 : 0;
  }
  return $self->{'truncated_flag'} || 0;
}

sub has_truncated_attribute {
    my ($self) = @_;
    return get_first_Attribute_value($self, 'otter_truncated');
}

sub add_truncated_attribute {
    my ($self) = @_;
    my $gene_attribs = $self->get_all_Attributes;

    my $truncated_attrib = Bio::EnsEMBL::Attribute->new(
        -CODE  => 'otter_truncated',
        -VALUE => 1,
        );
    push @$gene_attribs, $truncated_attrib;
    return;
}

# This is to be used by storing mechanism of GeneAdaptor,
# to simplify the loading during comparison.

sub last_db_version {
    my ($self, @args) = @_;

    if(@args) {
        $self->{_last_db_version} = shift @args;
    }
    return $self->{_last_db_version};
}

sub dissociate {
    my ($self) = @_;

    $self->dbID(undef);
    $self->adaptor(undef);
    foreach my $tran (@{ $self->get_all_Transcripts() }) {
        $tran->dbID(undef);
        $tran->adaptor(undef);
        # NB: exons do not need to be duplicated
        if ($tran->translation){
            $tran->translation->dbID(undef);
            $tran->translation->adaptor(undef);
        }
    }

    return;
}

sub attach_slice {
    my ($self, $slice) = @_;

    $self->slice($slice);
    foreach my $tsct (@{$self->get_all_Transcripts}) {
        $tsct->slice($slice);
    }
    foreach my $exon (@{$self->get_all_Exons}) {
        $exon->slice($slice);
    }

    return;
}

# keep track of all unique exons found so far to avoid making duplicates
# share exons of a gene among all transcripts
# need to be very careful about translation->start_exon and translation->end_Exon
sub prune_Exons {
  my ($self) = @_;

  my( %stable_key, %unique_exons );
  foreach my $tran (@{$self->get_all_Transcripts // []}) {
      my (@transcript_exons);
      foreach my $exon (@{$tran->get_all_Exons}) {
          my $exon_key = $exon->vega_hashkey;
          if (my $found = $unique_exons{$exon_key}) {
              # Use the found exon in the translation
              if ($tran->translation) {
                  if ($exon == $tran->translation->start_Exon) {
                      $tran->translation->start_Exon($found);
                  }
                  if ($exon == $tran->translation->end_Exon) {
                      $tran->translation->end_Exon($found);
                  }
              }
              # re-use existing exon in this transcript
              $exon = $found;
          } else {
              $unique_exons{$exon_key} = $exon;
          }
          push (@transcript_exons, $exon);
          # Make sure we don't have the same stable IDs
          # for different exons (different keys).
          if (my $stable = $exon->stable_id) {
              if (my $seen_key = $stable_key{$stable}) {
                  if ($seen_key ne $exon_key) {
                      warn  "Exon '$exon_key': already seen exon_id '$stable' on different exon '$seen_key'.\n";
                      $exon->stable_id(undef);
                  }
              } else {
                  $stable_key{$stable} = $exon_key;
              }
          }
      }
      $tran->flush_Exons;
      foreach my $exon (@transcript_exons) {
          $tran->add_Exon($exon);
      }
  }

  return;
}


sub set_biotype_status_from_transcripts {
    my ($self) = @_;

    my (%tsct_biotype, %tsct_status);
    foreach my $tsct (@{$self->get_all_Transcripts}) {
        # Ignore "not for VEGA" transcripts when setting gene biotype
        next if grep {$_->value eq 'not for VEGA'} @{ $tsct->get_all_Attributes('remark') };
        $tsct_biotype{$tsct->biotype}++;
        $tsct_status{ $tsct->status }++;
    }

    # Have already set status to KNOWN if Known was set in acedb.
    unless ($self->is_known) {
        # Not setting gene status to KNOWN if there is a transcript
        # with status KNOWN.  So KNOWN is only set if radio button in
        # otter is checked.
        my $status = 'UNKNOWN';
        if ($tsct_status{'PUTATIVE'} and keys(%tsct_status) == 1) {
            # Gene status is PUTATIVE if that is the only kind of transcript
            $status = 'PUTATIVE';
        }
        elsif ($tsct_status{'NOVEL'}

            or $tsct_biotype{'protein_coding'}
            or $tsct_biotype{'nonsense_mediated_decay'}

            or $tsct_biotype{'processed_transcript'}
            or $tsct_biotype{'non_coding'}
            or $tsct_biotype{'ambiguous_orf'}
            or $tsct_biotype{'retained_intron'}
            or $tsct_biotype{'antisense'}
            or $tsct_biotype{'disrupted_domain'}

            )
        {
            $status = 'NOVEL';
        }
        $self->status($status);
    }

    # For each polymorphic gene set the biotype according to that of it's transcripts:
    # 1. transcribed_unprocessed_pseudogene will also have a transcript, call them 'transcribed_unprocessed_pseudogene'
    # 2. same follows for 'transcribed_processed_pseudogene'.
    # 3. unitary_pseudogene with a transcript will be 'transcribed_unitary_pseudogene'.
    # 4. polymorphic_pseudogene with a coding transcript will be 'polymorphic'.
    # 5. polymorphic_pseudogene with a transcript will be 'polymorphic_pseudogene'.


    my $biotype = 'processed_transcript';
    if (my @pseudo = grep { /pseudo/i } keys %tsct_biotype) {
        if (@pseudo > 1) {
            throw(
                sprintf "More than one pseudogene type in gene %s (%s)",
                    get_name_Attribute_value($self),
                    join(', ', @pseudo)
                );
        }
        else {
            $biotype = $pseudo[0];
        }
    }
    elsif ($tsct_biotype{'protein_coding'}) {
        $biotype = 'protein_coding';
    }
    elsif (keys %tsct_biotype == 1
        and ($tsct_biotype{'ig_segment'}
          or $tsct_biotype{'ig_gene'}
          or $tsct_biotype{'transposon'}
          or $tsct_biotype{'artifact'}
          or $tsct_biotype{'tec'}
            )
        )
    {
        # If there is just 1 transcript biotype, then the gene gets it too.
        ($biotype) = keys %tsct_biotype;
    }
    $self->biotype($biotype);

    return;
}


=head2 status

 Arg [1]    : String (optional), status of the gene, KNOWN, PUTATIVE,...
 Description: Return or set the status of the gene. The value will
              be stored as an attribute.
 Returntype : String
 Exceptions : None

=cut

sub status {
  my ($self, $status) = @_;

  my $attributes = $self->get_all_Attributes('status');
  if ($status) {
    $self->{status} = $status;
    if (@$attributes) {
      $attributes->[0]->value($status);
    }
    else {
      $self->add_Attributes(Bio::EnsEMBL::Attribute->new(-code => 'status', -value => $status));
    }
  }
  elsif (!$self->{status} and @$attributes) {
    if (@$attributes > 1) {
      warning('You have multiple status attributes, using the first one '.$attributes->[0]);
    }
    $self->{status} = $attributes->[0]->value;
  }
  return $self->{status};
}


=head2 is_known

 Arg [1]    : None
 Description: Return true if the gene is of status 'KNOWN'
 Returntype : Boolean
 Exceptions : None

=cut

sub is_known {
  my ($self) = @_;

  return ($self->status eq 'KNOWN' || $self->status eq 'KNOWN_BY_PROJECTION');
}


1;

__END__

=head1 NAME - Bio::Vega::Gene

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


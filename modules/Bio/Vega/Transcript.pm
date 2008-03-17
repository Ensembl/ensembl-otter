package Bio::Vega::Transcript;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use base 'Bio::EnsEMBL::Transcript';
use Bio::Vega::Translation;

sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($transcript_author,$evidence_list)  = rearrange([qw(AUTHOR EVIDENCE)],@args);
  $self->transcript_author($transcript_author);
  if (defined($evidence_list)) {
	 if (ref($evidence_list) eq "ARRAY") {
		$self->evidence_list($evidence_list);
	 } else {
		$self->throw( "Argument to evidence must be an array ref. Currently [$evidence_list]");
	 }
  }
  return $self;
}

sub transcript_author {
  my ($self,$value) = @_;
  if( defined $value) {
	 if ($value->isa("Bio::Vega::Author")) {
		$self->{'transcript_author'} = $value;
	 } else {
		throw("Argument to transcript_author must be a Bio::Vega::Author object.  Currently is [$value]");
	 }
  }
  return $self->{'transcript_author'};
}

sub evidence_list {
    my ($self, $given_list) = @_;

    my $stored_list = $self->{'evidence_list'} ||= [];

    if ($given_list) {
            # don't copy the arrayref, copy the elements instead:
        my $class = 'Bio::Vega::Evidence';
        foreach my $evidence (@$given_list) {
            unless( $evidence->isa($class) ) {
                throw( "evidence_list can only store objects of '$class', not $evidence" );
            }
        }
        push @$stored_list, @$given_list;
    }
    return $stored_list;
}

# sub get_Evidence {
#   my $self = shift;
#   if ( ! exists $self->{'evidence' } ) {
#     if (!$self->adaptor() ) {
#       return [];
#     }
#
#     my $ta = $self->adaptor->db->get_TranscriptAdaptor();
#     $self->{'evidence'} = $ta->fetch_evidence($self);
#   }
#   return $self->{'evidence'};
# }
#
# sub add_Evidence {
#   my ($self,$evidence_list) = @_;
#
#   $self->{'evidence'} ||= [];
#
#   foreach my $evidence ( @$evidence_list ) {
#     if( ! $evidence->isa( "Bio::Vega::Evidence" )) {
# 		throw( "Argument to add_Evidence has to be an Bio::Vega::Evidence" );
#     }
#     push( @{$self->{'evidence'}}, $evidence );
#   }
#   return;
# }

sub truncate_to_Slice {
  my( $self, $slice ) = @_;
  # start and end exon are set to zero so that we can
  # safely use them in "==" without generating warnings
  # as we loop through the list of exons.
  ### Not used until we enable translation truncating
  my $start_exon = 0;
  my $end_exon   = 0;
  my( $tsl );
  if ($tsl = $self->translation) {
	 $start_exon = $tsl->start_Exon;
	 $end_exon   = $tsl->end_Exon;
  }
  my $exons_truncated = 0;
  my $in_translation_zone = 0;
  my $slice_length = $slice->length;
  my $ex_list = $self->get_all_Exons;
  for (my $i = 0; $i < @$ex_list;) {
	 my $exon = $ex_list->[$i];
	 my $exon_start = $exon->start;
	 my $exon_end   = $exon->end;
	 # now compare slice names instead of slice references
	 # slice references can be different not the slice names
	 if ($exon->slice->name != $slice->name or $exon_end < 1 or $exon_start > $slice_length) {
		#warn "removing exon that is off slice";
		### This won't work if get_all_Exons() ceases to return
		### a ref to the actual array of exons in the transcript.
		splice(@$ex_list, $i, 1);
		$exons_truncated++;
	 } else {
		#printf STDERR
		#    "Checking if exon %s is within slice %s of length %d\n"
		#    . "  being attached to %s and extending from %d to %d\n",
		#    $exon->stable_id, $slice, $slice_length, $exon->contig, $exon_start, $exon_end;
		$i++;
		my $trunc_flag = 0;
		if ($exon->start < 1) {
		  #warn "truncating exon that overlaps start of slice";
		  $trunc_flag = 1;
		  $exon->start(1);
		}
		if ($exon->end > $slice_length) {
		  #warn "truncating exon that overlaps end of slice";
		  $trunc_flag = 1;
		  $exon->end($slice_length);
		}
		$exons_truncated++ if $trunc_flag;
	 }
  }
  ### Hack until we fiddle with translation stuff
  if ($exons_truncated) {
	 $self->{'translation'}     = undef;
	 $self->{'_translation_id'} = undef;
  }
  return $exons_truncated;
}

# Duplicated in Bio::Vega::Gene
sub all_Attributes_string {
    my ($self) = @_;

    return join ('-',
        map {$_->code . '=' . $_->value}
        sort {$a->code cmp $b->code || $a->value cmp $b->value}
        @{$self->get_all_Attributes});
}

sub vega_hashkey {
  my $self=shift;
  my $seq_region_name   = $self->seq_region_name    || throw(  'seq_region_name must be set to generate correct vega_hashkey.');
  my $seq_region_start  = $self->seq_region_start   || throw( 'seq_region_start must be set to generate correct vega_hashkey.');
  my $seq_region_end    = $self->seq_region_end     || throw(   'seq_region_end must be set to generate correct vega_hashkey.');
  my $seq_region_strand = $self->seq_region_strand  || throw('seq_region_strand must be set to generate correct vega_hashkey.');
  my $biotype           = $self->biotype            || throw(          'biotype must be set to generate correct vega_hashkey.');
  my $status            = $self->status             || throw(           'status must be set to generate correct vega_hashkey.');

  my $exon_count = scalar @{$self->get_all_Exons} || throw("there are no exons for this transcript to generate correct vega_hashkey");
  my $description = $self->{'description'} ? $self->{'description'}: '' ;
  my $attrib_string = $self->all_Attributes_string;

  my $evidence_count = scalar(@{$self->evidence_list});

  return "$seq_region_name-$seq_region_start-$seq_region_end-$seq_region_strand-$biotype-$status-$exon_count-$description-$evidence_count-$attrib_string";
}

sub vega_hashkey_structure {
    return 'seq_region_name-seq_region_start-seq_region_end-seq_region_strand-biotype-status-exon_count-description-evidence_count-attrib_string';
}

sub vega_hashkey_sub {

  my $self = shift;
  my $evidence=$self->evidence_list();
  my $vega_hashkey_sub={};

  if (defined $evidence) {
	 foreach my $evi (@$evidence){
		my $e=$evi->name.$evi->type;
		$vega_hashkey_sub->{$e}='evidence';
	 }
  }
  my $exons=$self->get_all_Exons;

  foreach my $exon (@$exons){
	 $vega_hashkey_sub->{$exon->stable_id}='exon_stable_id';
  }
  return $vega_hashkey_sub;

}

sub translatable_Exons_vega_hashkey {
    my $self = shift;

    return join('+', map $_->vega_hashkey, @{$self->get_all_translateable_Exons});
}

# This is to be used by storing mechanism of GeneAdaptor,
# to simplify the loading during comparison.

sub last_db_version {
    my $self = shift @_;

    if(@_) {
        $self->{_last_db_version} = shift @_;
    }
    return $self->{_last_db_version};
}


1;

__END__

=head1 NAME - Bio::Vega::Transcript

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk

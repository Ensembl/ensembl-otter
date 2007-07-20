package Bio::Vega::Gene;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use base 'Bio::EnsEMBL::Gene';


sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($gene_author)  = rearrange([qw(AUTHOR)],@args);
  $self->gene_author($gene_author);
  return $self;
}

sub gene_author {
  my ($self,$value) = @_;
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

  my $self = shift;
  $self->{'source'} = shift if( @_ );
  return ( $self->{'source'} || "havana" );

}

# Duplicated in Bio::Vega::Transcript
sub all_Attributes_string {
    my ($self) = @_;
    
    return join ('-',
        map {$_->code . '=' . $_->value}
        sort {$a->code cmp $b->code || $a->value cmp $b->value}
        @{$self->get_all_Attributes});
}

sub vega_hashkey {
  my $self=shift;

  my $seq_region_name   = $self->seq_region_name    || throw(  'seq_region_name must be set to generate vega_hashkey');
  my $start             = $self->seq_region_start   || throw( 'seq_region_start must be set to generate vega_hashkey');
  my $end               = $self->seq_region_end     || throw(   'seq_region_end must be set to generate vega_hashkey');
  my $strand            = $self->seq_region_strand  || throw('seq_region_strand must be set to generate vega_hashkey');
  my $biotype           = $self->biotype            || throw(          'biotype must be set to generate vega_hashkey');
  my $status            = $self->status             || throw(           'status must be set to generate vega_hashkey');
  my $source            = $self->source             || throw(           'source must be set to generate vega_hashkey');
  my $tran_count = scalar @{$self->get_all_Transcripts}
    || throw("there are no transcripts for this gene to generate correct vega_hashkey");;
  my $description = $self->description || '';
  my $attrib_string = $self->all_Attributes_string;

  return "$seq_region_name-$start-$end-$strand-$biotype-$status-$source-$description-$tran_count-$attrib_string";
}

sub vega_hashkey_structure {
    return 'seq_region_name-seq_region_start-seq_region_end-seq_region_strand-biotype-status-source-description-transcript_count-all_attrib_string';
}

sub vega_hashkey_sub {

  my $self = shift;
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
  my( $self, $flag ) = @_;
  if (defined $flag) {
	 $self->{'truncated_flag'} = $flag ? 1 : 0;
  }
  return $self->{'truncated_flag'} || 0;
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

sub dissociate {
    my $self = shift @_;

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
}

# keep track of all unique exons found so far to avoid making duplicates
# share exons of a gene among all transcripts
# need to be very careful about translation->start_exon and translation->end_Exon
sub prune_Exons {
  my ($self) = @_;

  my( %stable_key, %unique_exons );
  foreach my $tran (@{$self->get_all_Transcripts}) {
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
				printf STDERR  "Already seen exon_id '$stable' on different exon\n";
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
}


1;

__END__

=head1 NAME - Bio::Vega::Gene

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk

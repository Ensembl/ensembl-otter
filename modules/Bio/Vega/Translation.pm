package Bio::Vega::Translation;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use base 'Bio::EnsEMBL::Translation';

sub vega_hashkey {
  my $self = shift;

  my $start_exon = $self->start_Exon;
  my $end_exon   = $self->end_Exon;
  
  my $in_coding = 0;
  my $coding_exons_hashkey = '';
  foreach my $exon (@{$self->get_all_Exons}) {
    unless ($in_coding) {
        if ($exon == $start_exon) {
            $in_coding = 1;
        } else {
            next;
        }
    }
    $coding_exons_hashkey .= $exon->vega_hashkey;
    last if $exon == $end_exon;
  }

  my $tl_start = $self->start;
  my $tl_end   = $self->end;

  return "$tl_start-$tl_end-$coding_exons_hashkey";
}

sub vega_hashkey_structure {
    return 'tl_start-tl_end-coding_exons_hashkey';
}

sub vega_hashkey_sub {

  my $self = shift;
  my $sel = $self->get_all_Attributes('_selenocystine');
  my $hashkey_sub={};
  if (defined $sel) {
	 foreach my $s (@$sel){
		$hashkey_sub->{$s->value}=1;
	 }
  }
  return $hashkey_sub;
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

=head1 NAME - Bio::Vega::Translation

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk

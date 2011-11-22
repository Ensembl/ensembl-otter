package Bio::Vega::Translation;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use base 'Bio::EnsEMBL::Translation';

sub vega_hashkey {
  my ($self) = @_;

  my $start_exon = $self->start_Exon;
  my $end_exon   = $self->end_Exon;
  unless ($start_exon and $end_exon) {
    throw("need both start_exon and end_exon for this translation to generate correct hashkey");
  }
  my $start_exon_hash_key = $start_exon->vega_hashkey;
  my $end_exon_hash_key   = $end_exon->vega_hashkey;

  my $tl_start =$self->start;
  my $tl_end   =$self->end;

  return "$start_exon_hash_key-$end_exon_hash_key-$tl_start-$tl_end";
}

sub vega_hashkey_structure {
    return 'start_exon_vega_hashkey-end_exon_vega_hashkey-tl_start-tl_end';
}

sub vega_hashkey_sub {
    my ($self) = @_;
    my $sel = $self->get_all_Attributes('_selenocysteine');
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
    my ($self, @args) = @_;

    if(@args) {
        $self->{_last_db_version} = shift @args;
    }
    return $self->{_last_db_version};
}

1;

__END__

=head1 NAME - Bio::Vega::Translation

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

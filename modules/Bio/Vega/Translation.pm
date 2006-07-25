package Bio::Vega::Translation;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use base 'Bio::EnsEMBL::Translation';

sub hashkey_sub {

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

sub hashkey {

  my $self=shift;
  my $start_exon=$self->start_Exon;
  my $end_exon  =$self->end_Exon;
  unless($start_exon) {
    throw("there is no start_exon for this gene to generate correct hashkey");
  }
  my $start_exon_hash_key=$start_exon->hashkey;
  my $end_exon_hash_key  =$end_exon->hashkey;

  my $tl_start =$self->start;
  my $tl_end   =$self->end;

  my $hashkey_main="$start_exon_hash_key-$end_exon_hash_key-$tl_start-$tl_end";
  return $hashkey_main;
}



1;

__END__

=head1 NAME - Bio::Vega::Translation

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk

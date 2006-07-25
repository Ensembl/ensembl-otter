package Bio::Vega::Slice;

use strict;
use base 'Bio::EnsEMBL::Slice';

sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  return $self;
}

sub get_all_Clone_Info  {

  my ($self, $dbtype) = @_;
  if(!$self->adaptor()) {
    warning('Cannot get Clone Info without attached adaptor');
    return [];
  }
  my $cia;
   if($dbtype) {
     my $db = $reg->get_db($self->adaptor()->db(), $dbtype);
     if(defined($db)){
       $cia = $reg->get_adaptor( $db->species(), $db->group(), "CloneInfo" );
     }
     else{
       $cia = $reg->get_adaptor( $self->adaptor()->db()->species(), $dbtype, "CloneInfo" );
     }
     if(!defined $cia) {
       warning( "$dbtype clone info not available" );
       return [];
     }
 } else {
    $cia =  $self->adaptor();
   }

  return $cia->fetch_all_by_Slice( $self);

}

1;

__END__

=head1 NAME - Bio::Vega::Slice

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk

package Bio::Otter::GeneSynonym;

use vars qw(@ISA);
use strict;
use Bio::Otter::GeneName;

@ISA = qw(Bio::Otter::GeneName);

sub new{
  my ($class, $name, $gene_info_id, $dbID) = @_;
  my $self = bless {}, $class;

  $self->name($name);
  $self->dbID($dbID);
  $self->gene_info_id($gene_info_id);	

  return $self;
}

1;

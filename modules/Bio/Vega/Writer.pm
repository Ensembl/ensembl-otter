package Bio::Vega::Writer;

use strict;
use Bio::Vega::Transform::PrettyPrint;
use Bio::EnsEMBL::Utils::Exception qw ( throw );

my %xml_builders;

sub DESTROY {
  my ($self) = @_;
  delete $xml_builders{$self};
}

sub new {
  my ($pkg) = @_;
  my $scalar;
  my $self = bless \$scalar, $pkg;
  $self->initialize;
  return $self;
}

sub getxml {

  my ($self,$type,$obj)=@_;
  my $xml;
  if (my $builder = $xml_builders{$self}{$type}) {
	 $xml=$self->$builder($obj);
  }
  else {
	 throw "this method not defined";
  }
  return $xml;
}

sub xml_builders {
  my ($self, $value) = @_;
  if ($value) {
	 $xml_builders{$self} = $value;
  }
  #die Dumper($xml_builders{$self});
  return $xml_builders{$self};
}

sub formatopentag{
  my ($self,$name,$indent)=@_;
  return ((' ' x $indent).'<'.$name.'>'."\n");
}

sub formatclosetag{
  my ($self,$name,$indent)=@_;
  return ((' ' x $indent).'</'.$name.">\n");
}

sub formatopenendtag{
  my ($self,$name,$indent,$value)=@_;
  $indent=$indent+2;
  return ((' ' x $indent).'<'.$name.'>'.$value.'</'.$name.">\n")
}

sub prettyprint{
  my ($self,$name,$value)=@_;
  my $element=Bio::Vega::Transform::PrettyPrint->new(-name=>$name,-value=>$value);
  return $element;
}

sub formatxml {
  my ($self,$pp)=@_;
  $pp->xmlformat($self->formatopentag($pp->name,$pp->indent));
  my $attribvals=$pp->attribvals;
  foreach my $a (@$attribvals){
	 $pp->xmlformat($self->formatopenendtag($a->name,$pp->indent,$a->value));
  }
  my $attribobjs=$pp->attribobjs;
  foreach my $a (@$attribobjs){
	 $a->indent($pp->indent+2);
	 $pp->xmlformat($self->formatxml($a));
  }
  $pp->xmlformat($self->formatclosetag($pp->name,$pp->indent));
  return $pp->xmlformat;
}

1;
__END__

=head1 NAME - Bio::Vega::Transform::XML

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

package Bio::Vega::Writer;

use strict;
use Bio::Vega::Transform::PrettyPrint;
use Bio::Vega::Utils::XmlEscape qw (xml_escape);

sub new {
  my ($pkg) = @_;
  my $self;
  return bless \$self, $pkg;
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
  if(!defined($name)) { warn "NAME is not defined"; }
  if(!defined($value)) { warn "VALUE is not defined where NAME='$name'"; }
  return ((' ' x $indent).'<'.$name.'>'.$value.'</'.$name.">\n")
}

sub prettyprint{
  my ($self,$name,$value)=@_;
  my $element = Bio::Vega::Transform::PrettyPrint->new(
    -name  => $name,
    -value => defined($value) ? xml_escape($value) : undef,
    );
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

=head1 NAME - Bio::Vega::Writer

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

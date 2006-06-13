package Bio::Vega::ContigInfo;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );

use base qw(Bio::EnsEMBL::Storable);


sub new {
  my($class,@args) = @_;
  my $self = bless {}, $class;
  my ($slice,$author,$attributes)  =
        rearrange([qw(SLICE AUTHOR ATTRIBUTES)],@args);
  $self->slice($slice);
  $self->author($author);
  $self->add_Attributes($attributes);
  return $self;
}

sub slice  {
  my ($self,$value) = @_;
  if(defined($value) ){
	 if (!ref($value) || !$value->isa('Bio::EnsEMBL::Slice')) {
		$self->throw('slice argument must be a Bio::EnsEMBL::Slice');
	 }
	 $self->{'slice'} = $value;
  }
  return $self->{'slice'};
}

sub author{
  my $self = shift;
  my $value = shift if ( @_ );
  if (defined($value) ){
	 if (!ref($value) || !$value->isa("Bio::Vega::Author")) {
		$self->throw("Argument is not a Bio::Vega::Author");
	 }
	 $self->{'author'}=$value;
  }
  return $self->{'author'};
}

sub created_date  {
  my $self = shift;
  return $self->{'created_date'};
}

sub current_status  {
  my $self = shift;
  return $self->{'current_status'};
}

sub add_Attributes  {
  my ($self,$attribref) = @_;
  if( ! exists $self->{'attributes'} ) {
    $self->{'attributes'} = [];
  }
  foreach my $attrib ( @$attribref ) {
    if( ! $attrib->isa( "Bio::EnsEMBL::Attribute" )) {
     $self->throw( "Argument to add_Attribute has to be an Bio::EnsEMBL::Attribute" );
    }
    push( @{$self->{'attributes'}}, $attrib );
  }
  return;
}


sub get_all_Attributes  {
  my $self = shift;
  my $attrib_code = shift;
  if( ! exists $self->{'attributes' } ) {
    if(!$self->adaptor() ) {
      return [];
    }

    my $attribute_adaptor = $self->adaptor();
    $self->{'attributes'} = $attribute_adaptor->fetch_all_by_CloneInfo($self);
  }
  if( defined $attrib_code ) {
    my @results = grep { uc($_->code()) eq uc($attrib_code) }
    @{$self->{'attributes'}};
    return\@ results;
  } else {
    return $self->{'attributes'};
  }

}

1;

__END__

=head1 NAME - Bio::Vega::ContigInfo.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk


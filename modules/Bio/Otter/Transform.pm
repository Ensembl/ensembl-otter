=pod

=head1 Bio::Otter::Transform

=head1 DESCRIPTION

This is a bit of an experiment, and is designed as a base class
for xml parsing and transformation to otter objects, with the 
goal of moving it out of Converter and moving to stream based method.

=head1 USAGE

Try this and see first implementation in Bio::Otter::Lace::Client
which uses the Bio::Otter::Transform::DataSets child.

  my $transform = Bio::Otter::Transform->new();
  
  # this returns the XML::Parser obj
  my $p = $transform->my_parser();
  $p->parse($xml);

  # get the objects created
  $transform->objects;

=head1 Note to subclasses

You need to implement {start,end,char}_handler methods to create
your object list, even if they're just "sub end_handler{ }".

=head1 BUGS

There's probably a better way to do this, but it kinda works at the 
moment for Datasets at least.

=head1 AUTHOR

Roy Storey rds@sanger.ac.uk

=cut


package Bio::Otter::Transform;

use strict;
use warnings;

use XML::Parser;
use Bio::Otter::Version;

sub new{
    my $pkg = shift;

    my $self = bless({}, ref($pkg) || $pkg);

    return $self;
}

sub my_parser{
    my ($self) = @_;
    my $p1 = new XML::Parser(Style => 'Debug',
                             Handlers => {
                                 Start => sub { 
                                     $self->start_handler(@_);
                                 },
                                 End => sub {
                                     $self->end_handler(@_);
                                 },
                                 Char => sub { 
                                     $self->char_handler(@_);
                                 }
                             });

    return $p1;
}

sub default_handler{
    my $c = (caller(1))[3];
    print "$c -> @_\n";
}

sub start_handler{
    my $self = shift;
    my $xml  = shift;
    my $ele  = lc shift;
    $self->_check_version(@_) if $ele eq 'otter';
}
sub _check_version{
    my $self = shift;
    my $attr = {@_};
    my $schemaVersion = $attr->{'schemaVersion'} || '';
    my $xmlVersion    = $attr->{'xmlVersion'}    || '';
    error_exit("Wrong schema version, expected '$SCHEMA_VERSION' not '$schemaVersion'\n")
        unless ($schemaVersion && $schemaVersion <= $SCHEMA_VERSION);
    # $schemaVersion xml client receives must be older than client understands ($SCHEMA_VERSION)
    error_exit("Wrong xml version, expected '$XML_VERSION' not '$xmlVersion'\n")
        unless ($xmlVersion    && $xmlVersion    <= $XML_VERSION);
    #### $xmlVersion xml client receives must be older than client understands ($XML_VERSION)
}
sub error_exit{
    print STDOUT "@_";
    print STDERR "@_";
    exit(1);
}
sub end_handler{
    my $self = shift;
    $self->default_handler(@_);
}
sub char_handler{
    my $self = shift;
    $self->default_handler(@_);
}

sub set_property{
    my ($self, $prop_name, $value) = @_;
    return undef unless $prop_name;
    if($value){
        $self->{'_properties'}->{$prop_name} = $value;
    }
    return $self->{'_properties'}->{$prop_name};
}
sub get_property{
    my $self = shift;
    return $self->set_property(@_);
}

sub objects{
    my $self = shift;
    return $self->{'_objects'};
}
sub add_object{
    my $self = shift;
    push(@{$self->{'_objects'}}, shift) if @_;
    
}

# END
1; # return true;

__END__

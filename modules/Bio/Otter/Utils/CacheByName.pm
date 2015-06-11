package Bio::Otter::Utils::CacheByName;

# cache objects by name - objects must have name() attribute

use strict;
use warnings;

my %_name_attribute;            # inside-out since we use the blessed hashref as the cache

sub DESTROY {
    my ($self) = @_;
    delete $_name_attribute{$self};
    return;
}

sub new {
    my ($class, $name_attribute) = @_;
    my $self = bless {}, $class;
    $self->_name_attribute($name_attribute // 'name');
    return $self;
}

sub _name_attribute {
    my ($self, @args) = @_;
    ($_name_attribute{$self}) = @args if @args;
    my $_name_attribute = $_name_attribute{$self};
    return $_name_attribute;
}

sub set {
    my ($self, $obj, $not_unique_sub) = @_;

    my $na = $self->_name_attribute;
    my $name = $obj->$na;
    if ($not_unique_sub and $self->{$name}) {
        my $replace = $not_unique_sub->($obj, $name);
        return unless $replace;
    }

    return $self->{$name} = $obj;
}

sub get {
    my ($self, $name) = @_;
    return $self->{$name};
}

sub get_or_new {
    my ($self, $name, $constructor) = @_;
    if (my $obj = $self->get($name)) {
        return $obj;
    } else {
        $obj = $constructor->($name);
        return $self->set($obj);
    }
}

sub get_or_this {
    my ($self, $obj) = @_;
    my $na = $self->_name_attribute;
    if (my $existing = $self->get($obj->$na)) {
        return $existing;
    } else {
        return $self->set($obj);
    }
}

sub delete {
    my ($self, $name) = @_;
    return delete $self->{$name};
}

sub delete_object {
    my ($self, $obj) = @_;
    my $na = $self->_name_attribute;
    return $self->delete($obj->$na);
}

sub names {
    my ($self) = @_;
    return keys %$self;
}

sub objects {
    my ($self) = @_;
    return values %$self;
}

sub empty {
    my ($self) = @_;
    delete $self->{$_} for $self->names;
    return;
}

1;

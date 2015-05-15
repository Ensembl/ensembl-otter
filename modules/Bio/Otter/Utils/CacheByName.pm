package Bio::Otter::Utils::CacheByName;

# cache objects by name - objects must have name() attribute

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub set {
    my ($self, $obj, $not_unique_sub) = @_;

    my $name = $obj->name;
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
    if (my $existing = $self->get($obj->name)) {
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
    return $self->delete($obj->name);
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


### Bio::Otter::SQL::Qualifier

package Bio::Otter::SQL::Qualifier;

use strict;

sub new {
    return bless {}, shift;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub value {
    my( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_value'} = $value;
    }
    return $self->{'_value'};
}

sub string {
    my $self = shift;
    
    return $self->name .'='. $self->value;
}

1;

__END__

=head1 NAME - Bio::Otter::SQL::Qualifier

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk



### Bio::Otter::SQL::Clause::KeyDefinition::Column

package Bio::Otter::SQL::Clause::KeyDefinition::Column;

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

sub precision {
    my( $self, $precision ) = @_;
    
    if ($precision) {
        $self->{'_precision'} = $precision;
    }
    return $self->{'_precision'};
}

sub string {
    my $self = shift;
    
    my $str = $self->name;
    if (my $p = $self->precision) {
        $str .= " ($p)";
    }
    return $str;
}

1;

__END__

=head1 NAME - Bio::Otter::SQL::Clause::KeyDefinition::Column

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


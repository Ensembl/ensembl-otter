
### Bio::Otter::Lace::Source::Item

package Bio::Otter::Lace::Source::Item;

use strict;
use warnings;
use Carp;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub string {
    confess "string() not implemented in ", ref(shift);
}

sub is_Bracket {
    confess "is_Bracket() not implemented in ", ref(shift);
}

sub indent {
    my ($self, $indent) = @_;

    if (defined $indent) {
        $self->{'_indent'} = $indent;
    }
    return $self->{'_indent'};
}

sub name {
    my ($self, $name) = @_;

    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub selected {
    my($self, $flag) = @_;

    if (defined $flag) {
        $self->{'_selected'} = $flag ? 1 : 0;
    }
    return $self->{'_selected'};
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::Source::Item

=head1 DESCRIPTION

Base class for item data objects drawn in the ColumnChooser window.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


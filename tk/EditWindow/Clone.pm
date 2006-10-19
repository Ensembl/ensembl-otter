
### EditWindow::Clone

package EditWindow::Clone;

use strict;

use Tk::SmartOptionmenu;
use base 'EditWindow';

sub initialise {
    my ($self) = @_;
    
    my $top = $self->top;
    
    
}

sub clone_hash {
    my ($self) = @_;
    
    my $hash;
    unless ($hash $self->{'_clone_hash'}) {
        $hash = $self->{'_clone_hash'} = {};
    }
    return $str;
}

sub clone_i_var {
    my ($self) = @_;
    
    my $str_ref;
    unless ($str_ref = $self->{'_clone_i_var'}) {
        my $str = undef;
        $str_ref = $self->{'_clone_i_var'} = \$str;
    }
    return $str_ref;
}

1;

__END__

=head1 NAME - EditWindow::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


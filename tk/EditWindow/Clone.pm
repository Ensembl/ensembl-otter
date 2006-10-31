
### EditWindow::Clone

package EditWindow::Clone;

use strict;

use Tk::SmartOptionmenu;
use base 'EditWindow';

sub initialise {
    my ($self) = @_;
    
    my $top = $self->top;
    
    my $choose = $top->SmartOptionmenu(
        -options    => $self->clone_choices,
        -variable   => $self->clone_i_var,
        -command => sub{
                printf STDERR "Clone index = %d\n", ${$self->clone_i_var};
            },
        )->pack(-side => 'left');
}

sub clone_choices {
    my ($self) = @_;
    
    my $choices = [];
    my @all_clones = $self->XaceSeqChooser->Assembly->get_all_Clones;
    for (my $i = 0; $i < @all_clones; $i++) {
        my $cl = $all_clones[$i];
        my $choice = sprintf "%s.%d  %s",
            $cl->accession,
            $cl->sequence_version,
            $cl->clone_name;
        push(@$choices, [$choice, $i]);
    }
    return $choices;
}

sub clone_i_var {
    my ($self) = @_;
    
    my $str_ref;
    unless ($str_ref = $self->{'_clone_i_var'}) {
        my $str = 0;
        $str_ref = $self->{'_clone_i_var'} = \$str;
    }
    return $str_ref;
}

sub XaceSeqChooser {
    my( $self, $XaceSeqChooser ) = @_;
    
    if ($XaceSeqChooser) {
        $self->{'_XaceSeqChooser'} = $XaceSeqChooser;
    }
    return $self->{'_XaceSeqChooser'};
}

sub write_access {
    my( $self ) = @_;
    
    return $self->XaceSeqChooser->write_access;
}

1;

__END__

=head1 NAME - EditWindow::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


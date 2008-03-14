
### EditWindow::LocusName

package EditWindow::LocusName;

use strict;
use Carp;

use Tk::SmartOptionmenu;
use base 'EditWindow';

sub initialise {
    my ($self) = @_;
    
    my $top = $self->top;

    my $name_frame = $top->Frame(
        -border     => 3,
        )->pack(-side => 'top', -fill => 'x');

    my ($chosen, $menu_list) = $self->make_menu_choices;
    $name_frame->Label(-text => 'Rename locus: ')->pack(-side => 'left');
    $name_frame->SmartOptionmenu(
        -options    => $menu_list,
        -variable   => \$chosen,
        -command    => sub {
            warn "Chosen locus is ", $self->chosen_name;
        },
    )->pack(-side => 'left');
    $self->{'_chosen_name'} = \$chosen;
    
    my $new_name = $name_frame->Entry(-width => 20)->pack(-side => 'left');
    $self->{'_new_name_entry'} = $new_name;
    
    my $do_rename = sub { $self->do_rename };
    $name_frame->Button(-text => 'Rename', -command => $do_rename)->pack(-side => 'left');
    
    $top->bind('<Destroy>', sub{ $self = undef; });
}

sub do_rename {
    my ($self) = @_;
    
    my $old_name = $self->chosen_name;
    my $new_name = $self->get_new_name;
    warn "Renaming '$old_name' to '$new_name'";
}

sub chosen_name {
    my ($self) = @_;
    
    return ${$self->{'_chosen_name'}};
}

sub get_new_name {
    my ($self) = @_;
    
    return $self->{'_new_name_entry'}->get;
}

sub XaceSeqChooser {
    my ($self, $xc) = @_;
    
    if ($xc) {
        $self->{'_xace_seq_chooser'} = $xc;
    }
    return $self->{'_xace_seq_chooser'};
}

sub make_menu_choices {
    my ($self) = @_;
    
    my $xc = $self->XaceSeqChooser;
    my $sel_locus_name;
    foreach my $name ($xc->list_selected_subseq_names) {
        my $sub = $xc->get_SubSeq($name) or next;
        my $locus = $sub->Locus or next;
        $sel_locus_name = $locus->name;
        last;
    }
    my @locus_name = $xc->list_Locus_names;
    unless ($sel_locus_name) {
        $sel_locus_name = $locus_name[@locus_name / 2];
    }
    my $menu_list = [ map { [$_, $_] } @locus_name ];
    return ($sel_locus_name, $menu_list);
}

sub DESTROY {
    my ($self) = @_;
    
    warn "Destroying a '", ref($self), "'";
}

1;

__END__

=head1 NAME - EditWindow::LocusName

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


### CanvasWindow::SearchWindow

package CanvasWindow::SearchWindow;

use strict;
use Carp;
use base 'CanvasWindow';
use Bio::Otter::Lace::Locator;

sub Client {
    my( $self, $Client ) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub DataSet {
    my( $self, $DataSet ) = @_;
    
    if($DataSet) {
        $self->{_DataSet} = $DataSet;
    }
    return $self->{_DataSet};
}

sub SequenceSetChooser {
    my( $self, $SequenceSetChooser ) = @_;

    if ($SequenceSetChooser) {
        $self->{'_SequenceSetChooser'} = $SequenceSetChooser;
    }
    return $self->{'_SequenceSetChooser'};
}

sub found_elements {
    my ($self, $new_elements) = @_;

    if($new_elements) {
        $self->{_found_elements} = $new_elements;
    }

    return $self->{_found_elements} ||= [];
}

sub search_field {
    my ($self) = @_;

    my $scalar = '';

    return $self->{_search_field} ||= \$scalar;
}

sub do_search {
    my ($self) = @_;

    foreach my $oldresult (@{$self->found_elements}) {
        $oldresult->packForget();
    }
    $self->found_elements([]);

    my $qnames = [ split(/[\s,]+/, ${$self->search_field()} ) ];

    my $window = $self->canvas()->toplevel();

    $window->configure(-cursor => 'watch'); # 'waiting state'
    $window->update(); # proved to be necessary

    my $results_list = $self->Client()->find_string_match_in_clones($self->DataSet->name(), $qnames);
    
    foreach my $locator (@$results_list) {
        my $result_frame = $self->{_results_frame}->Frame(
        )->pack(-side => 'top', -fill => 'x');

        my $label = $result_frame->Label(
            -text =>
                 $locator->qname()
                .' ['
                .$locator->qtype()
                .']  found on '
                .$locator->clone_name()
                .'  in '
        )->pack(-side => 'left', -fill => 'x');

        foreach my $asm (@{$locator->assemblies()}) {
            my $button = $result_frame->Button(
                -text => $asm,
                -command => sub {
                    print STDERR "Opening $asm...\n";
                    $self->SequenceSetChooser()->open_sequence_set_by_ssname_clonename(
                            $asm, $locator->clone_name()
                    );
                },
            )->pack(-side => 'right');
        }
        
        push @{$self->found_elements}, $result_frame;
    }

    $self->fix_window_min_max_sizes;

    $window->configure(-cursor => undef); # 'active state'
    $window->update(); # proved to be necessary
}

sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);
    
    $self->{_results_frame} = $self->canvas->Frame();
    $self->canvas->createWindow( 5, 5,
        -window => $self->{_results_frame},
        -anchor => 'nw',
        -tags => 'metaframe',
    );
    $self->canvas->configure(-background => $self->{_results_frame}->cget('-background') );

    my $control_frame = $self->canvas()->toplevel()->Frame->pack(-side => 'top', -fill => 'x');

    my $search_entry = $control_frame->Entry(
        -textvariable => $self->search_field(),
    )->pack(-side => 'left', -fill => 'x', -expand => 1);

    my $quit_button = $control_frame->Button(
        -text       => 'Close',
        -command    => sub { $self->hide_me() },
    )->pack(-side => 'right');
        
    my $search_button = $control_frame->Button(
        -text    => 'Search',
        -command => sub { $self->do_search(); },
    )->pack(-side => 'right');

        # functional bindings:
    my $window = $self->canvas()->toplevel();
    $search_entry->bind('<Return>', sub { $self->do_search(); } );
    $window->protocol('WM_DELETE_WINDOW', sub { $self->hide_me(); } );

        # anti-disfunctional bindings:
    $search_button->bind('<Destroy>', sub { $self = undef });
    $search_entry->bind('<Destroy>', sub { $self = undef });
    $quit_button->bind('<Destroy>', sub { $self = undef });
    $window->bind('<Destroy>', sub { $self = undef });

    return $self;
}

sub show_me {
    my ($self) = @_;

    my $window = $self->canvas()->toplevel();

    $window->deiconify();
    $window->raise();
    $window->focus();
}

sub hide_me {
    my ($self) = @_;

    my $window = $self->canvas()->toplevel();

    $window->withdraw();
}

1;

__END__

=head1 NAME - CanvasWindow::SearchWindow

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk


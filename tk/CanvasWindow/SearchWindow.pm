### CanvasWindow::SearchWindow

package CanvasWindow::SearchWindow;

use strict;
use Carp;
use base 'CanvasWindow';
use Bio::Otter::Lace::Locator;
use Hum::Sort 'ace_sort';

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
    my ($self, $value) = @_;

    my $scalar = '';
    $self->{_search_field} ||= \$scalar;

    if(defined($value)) {
        ${ $self->{_search_field} } = $value;
    }

    return $self->{_search_field};
}

sub do_search {
    my ($self) = @_;

    foreach my $oldresult (@{$self->found_elements}) {
        $oldresult->packForget();
    }
    $self->found_elements([]);

    my $qnames = [ split(/[\s,]+/, ${$self->search_field()} ) ];

    $self->watch_cursor();

    my $results_list = $self->Client()->find_string_match_in_clones($self->DataSet->name(), $qnames);
    
    foreach my $locator (sort { ace_sort($a->qname(), $b->qname()) } @$results_list) {

        my $result_frame = $self->{_results_frame}->Frame(
        )->pack(-side => 'top', -fill => 'x');

        push @{$self->found_elements}, $result_frame;

        my $qname        = $locator->qname();
        my $qtype        = $locator->qtype();
        my $ssname       = $locator->assembly();
        my $clone_names  = $locator->component_names();
        my $clone_number = scalar(@$clone_names);

        if($clone_number) {

                # PREPARE TO set the subset in the SequenceSet
            my $ds = $self->DataSet();
            my $ss = $ds->get_SequenceSet_by_name($ssname);
            my $subset_tag = "$ssname:Found:$qname";

            $qtype=~s/_/ /g; # underscores become spaces for readability

            my $label1 = $result_frame->Label(
                -text => "$qname [$qtype] found on ",
            )->pack(-side => 'left', -fill => 'x');

            my $button = $result_frame->Button(
                -text => "$clone_number clone".(($clone_number>1) ? 's' : '')." on $ssname",
                -command => sub {
                    print STDERR "Opening '$subset_tag'...\n";

                    # See whether this step can be omittied in the new implementation
                    #
                    #    # pre-load the clone sequences, if they have not been loaded yet
                    #unless(defined($ss->CloneSequence_list())) {
                    #    $ds->fetch_all_CloneSequences_for_SequenceSet($ss, 1);
                    #}
                        # ACTUALLY SET the subset in the SequenceSet
                    $ss->set_subset($subset_tag, $clone_names);

                    $self->SequenceSetChooser()->open_sequence_set_by_ssname_subset(
                            $ssname, $subset_tag
                    );
                },
            )->pack(-side => 'left');


            my $center_index = int(($clone_number-1)/2);
            my %show_clone_index = (
                0               => 1,               # always show the first one
                ($center_index==2) ? (1 => 1) : (), # show the second one if there is only one in the gap
                $center_index   => 1,               # always show the middle one
                ($clone_number==5) ? (3 => 1) : (), # show the fourth one if there is only one in the gap
                $clone_number-1 => 1,               # always show the last one
            );

            my @clone_names_to_show = ();
            my $skipped_number = 0;
            foreach my $i (0..scalar(@$clone_names)-1) {
                if($show_clone_index{$i}) {
                    if($skipped_number) {
                        push @clone_names_to_show, '...';
                        $skipped_number = 0;
                    }
                    my $clone_name = $clone_names->[$i];
                    push @clone_names_to_show, $clone_name;
                } else {
                    $skipped_number++;
                }
            }

            my $label2 = $result_frame->Label(
                -text => ' [ '.join(', ', @clone_names_to_show).' ]',
            )->pack(-side => 'left', -fill => 'x');

        } else {
            my $label = $result_frame->Label(
                -text => "$qname not found",
            )->pack(-side => 'left', -fill => 'x');
        }
    }

    $self->fix_window_min_max_sizes;

    $self->default_cursor();
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

        # the 'help' message pretends to be one of the search results:
    my $help_frame = $self->{_results_frame}->Frame(
    )->pack(-side => 'top', -fill => 'x');

    push @{$self->found_elements}, $help_frame;

    $help_frame->Label(
        -text => "Search for:\n\n"
                ."* Locus names or synonyms,\n"
                ."* Gene/Transcript/Translation/Exon stable_IDs or\n"
                ."* international or EMBL clone names",
        -justify => 'left',
    )->pack(-side => 'top', -fill => 'both');

        # controls are all grouped below:
    my $control_frame = $self->canvas()->toplevel()->Frame->pack(-side => 'top', -fill => 'x');

    my $clear_button = $control_frame->Button(
        -text       => 'Clear',
        -command    => sub { $self->search_field('') },
    )->pack(-side => 'left');
        
    my $search_entry = $control_frame->Entry(
        -textvariable => $self->search_field(),
        -width => 36,
    )->pack(-side => 'left', -fill => 'x', -expand => 1);

    my $close_button = $control_frame->Button(
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
    $close_button->bind('<Destroy>', sub { $self = undef });
    $window->bind('<Destroy>', sub { $self = undef });

    $self->fix_window_min_max_sizes;

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


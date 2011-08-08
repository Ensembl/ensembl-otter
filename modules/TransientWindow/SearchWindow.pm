
package TransientWindow::SearchWindow;

use strict;
use warnings;
use base 'TransientWindow';

my $DEFAULT_SEARCH_TEXT  = '';
my $DEFAULT_SEARCH_TYPE  = 'locus';
my $DEFAULT_CONTEXT_SIZE = 1;

sub initialise{
    my ($self, @args) = @_;
    $self->SUPER::initialise(@args);
    $self->text_variable_ref('search_text',  $DEFAULT_SEARCH_TEXT,  1);
    $self->text_variable_ref('search_type',  $DEFAULT_SEARCH_TYPE,  1);
    $self->text_variable_ref('context_size', $DEFAULT_CONTEXT_SIZE, 1);
    return;
}

sub draw {
    my ($self) = @_;
    return if $self->{'_drawn'};

    # get the callbacks required
    my $doSearch = $self->action('doSearch');

    my $search_window = $self->window;
    my $label         =
      $search_window->Label(-text => "Use spaces to separate multiple terms")
      ->pack(-side => 'top');
    my $search_entry = $search_window->Entry(
        -width        => 30,
        -relief       => 'sunken',
        -borderwidth  => 2,
        -textvariable => $self->text_variable_ref('search_text'),

        #-font         => 'Helvetica-14',
      )->pack(
        -side => 'top',
        -padx => 5,
        -fill => 'x',
      );

    # bind searching to return
    # this bind is a bit of a bind. The $search_entry widget is implicitly
    # passed to $doSearch as first arg.
    # this should work according to Ch15 pp364 Mastering Perl/Tk
    # $search_entry->bind('<Return>' => [ $self, $doSearch ]); # but doesn't
    # $search_entry->bind('<Return>' => [ $self => 'DESTROY' ]); # This calls the DESTROY method
    # I've ended up doing this rather than fool around in the callback.
    $search_entry->bind(
        '<Return>' => [ sub { shift; $doSearch->(@_) }, $self ]);

    ## radio buttons
    my $radio_frame = $search_window->Frame()->pack(
        -side => 'top',
        -pady => 5,
        -fill => 'x'
    );
    my $locus_radio = $radio_frame->Radiobutton(
        -text     => 'locus',
        -variable => $self->text_variable_ref('search_type'),
        -value    => 'locus',
      )->pack(
        -side => 'left',
        -padx => 5,
      );
    my $stable_radio = $radio_frame->Radiobutton(
        -text     => 'stable id',
        -variable => $self->text_variable_ref('search_type'),
        -value    => 'stable_id',
      )->pack(
        -side => 'left',
        -padx => 5,
      );
    my $clone_radio = $radio_frame->Radiobutton(
        -text     => 'intl. clone name or accession[.version]',
        -variable => $self->text_variable_ref('search_type'),
        -value    => 'clone'
      )->pack(
        -side => 'right',
        -padx => 5
      );

    ## search cancel buttons
    my $search_cancel_frame = $search_window->Frame()->pack(
        -side => 'bottom',
        -padx => 5,
        -pady => 5,
        -fill => 'x',
    );

    my $find_button = $search_cancel_frame->Button(
        -text    => 'Search',
        -command => [ $doSearch, $self ],
    )->pack(-side => 'left');

    my $context_label =
      $search_cancel_frame->Label(-text => ' with context:',)
      ->pack(-side => 'left');
    my $context_entry = $search_cancel_frame->Entry(
        -width        => 5,
        -relief       => 'sunken',
        -borderwidth  => 2,
        -textvariable => $self->text_variable_ref('context_size'),

        #-font         => 'Helvetica-14',
      )->pack(
        -side => 'left',
        -padx => 5,
      );

    my $cancel_button = $search_cancel_frame->Button(
        -text    => 'Cancel',
        -command => $self->hide_me_ref,
    )->pack(-side => 'right');

    my $reset_button = $search_cancel_frame->Button(
        -text    => 'Reset',
        -command => sub {
            $self->text_variable_ref('search_text',  $DEFAULT_SEARCH_TEXT,  1);
            $self->text_variable_ref('search_type',  $DEFAULT_SEARCH_TYPE,  1);
            $self->text_variable_ref('context_size', $DEFAULT_CONTEXT_SIZE, 1);
        },
    )->pack(-side => 'right');

    my $clear_button = $search_cancel_frame->Button(
        -text    => 'Clear',
        -command => sub {
            my $ref = $self->text_variable_ref('search_text', '', 1);
        }
    )->pack(-side => 'right');

    # delete the callbacks as they might contain circular references.
    # THIS MUST BE DONE!!
    $self->delete_action('doSearch');
    $self->delete_all_actions();

    # Break circular references held by closures above
    $clear_button->bind('<Destroy>', sub { $self = undef; });

    $self->{'_drawn'} = 1;
    return;
}

1;





__END__



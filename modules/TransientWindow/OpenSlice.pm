package TransientWindow::OpenSlice;

use strict;
use warnings;

use base qw( TransientWindow );

my $DEFAULT_SLICE_SIZE = 1e6;

sub initialise{
    my ($self, @args) = @_;
    $self->SUPER::initialise(@args);
    my $slice_start = ${$self->text_variable_ref('slice_start')};
    my $slice_end ||= $slice_start + $DEFAULT_SLICE_SIZE;
    $self->text_variable_ref('slice_end', $slice_end, 1);
    return;
}

sub draw{
    my ($self) = @_;
    return if $self->{'_drawn'};

    my $slice_window = $self->window;
    # The clones do not get truncated.
    my $label =
        $slice_window->Label(
            -text =>
            qq(Enter chromosome coordinates for the start and end of the slice) .
            qq( to open the clones contained.)
        )->pack(-side => 'top');
    $label->bind('<Destroy>' , sub { $self = undef });

    my $entry_frame  = $slice_window->Frame()->pack(-side => 'top', 
                                                   -padx =>  5,
                                                   -pady =>  5,
                                                   -fill => 'x'
                                                   );   
    my $min_label       = $entry_frame->Label(-text => "Slice:  start")->pack(-side   =>  'left');
    my $slice_min_entry = $entry_frame->Entry(-width        => 15,
                                              -relief       => 'sunken',
                                              -borderwidth  => 2,
                                              -textvariable => $self->text_variable_ref('slice_start'),
                                              #-font       =>   'Helvetica-14',   
                                              )->pack(-side => 'left', 
                                                      -padx => 5,
                                                      -fill => 'x'
                                                      );
    my $auto_slice_end = sub {
        my $min = ${$self->text_variable_ref('slice_start')};
        my $max = ${$self->text_variable_ref('set_end')};
        $self->text_variable_ref('slice_end', 
                                 $min + $DEFAULT_SLICE_SIZE > $max ? $max : $min + $DEFAULT_SLICE_SIZE,
                                 1
                                 );
    };
    $slice_min_entry->bind('<FocusOut>', $auto_slice_end);

    my $max_label       = $entry_frame->Label(-text => " end ")->pack(-side => 'left');
    $max_label->bind('<Destroy>' , sub { $self = undef }  );
    my $slice_max_entry = $entry_frame->Entry(-width        => 15,
                                              -relief       => 'sunken',
                                              -borderwidth  => 2,
                                              -textvariable => $self->text_variable_ref('slice_end'),
                                              #-font       =>   'Helvetica-14',   
                                              )->pack(-side => 'left', 
                                                      -padx => 5,
                                                      -fill => 'x',
                                                      );
    $entry_frame->bind('<Destroy>' , sub { $self = undef }  );

    my $run_cancel_frame = $slice_window->Frame()->pack(-side => 'bottom', 
                                                        -padx =>  5,
                                                        -pady =>  5,
                                                        -fill => 'x'
                                                        );  
    my $runLace = $self->action('runLace');
    my $run_button = $run_cancel_frame->Button(-text    => 'Run lace',
                                               -command => [ $runLace, $self ],
                                               )->pack(-side => 'left');

    my $cancel_button = $run_cancel_frame->Button(-text    => 'Cancel',
                                                  -command => $self->hide_me_ref,
                                                  )->pack(-side => 'right');

    $run_cancel_frame->bind('<Destroy>' , sub { $self = undef }  );

    # clean up circulars
    $self->delete_all_actions();

    $self->{'_drawn'} = 1;
    return;
}

1;





__END__



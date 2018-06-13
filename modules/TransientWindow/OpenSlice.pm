=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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
    $self->text_variable_ref('slice_len', $DEFAULT_SLICE_SIZE, 1);
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

    my $entry_frame =
        $slice_window->Frame()->pack(
            -side => 'top', 
            -padx =>  5,
            -pady =>  5,
            -fill => 'x'
        );
    my $len_frame =
        $slice_window->Frame()->pack(
            -side => 'top', 
            -padx =>  5,
            -pady =>  5,
            -expand => 1,
        );

    my $min_label =
        $entry_frame->Label(
            -text => "Slice:  start"
        )->pack(-side => 'left');
    my $slice_min_entry =
        $entry_frame->Entry(
            -width        => 15,
            -relief       => 'sunken',
            -borderwidth  => 2,
            -textvariable => $self->text_variable_ref('slice_start'),
            #-font       =>   'Helvetica-14',   
        )->pack(
            -side => 'left', 
            -padx => 5,
            -fill => 'x',
        );
    my $len_entry;
    my $update_len = sub {
        my $sref = $self->text_variable_ref('slice_start');
        my $eref = $self->text_variable_ref('slice_end');
        my $lref = $self->text_variable_ref('slice_len');
        $$lref = $$eref - $$sref + 1;
        my $bg = 'white';
        $bg = 'orange' if $$lref > 5E6; # vague and arbitrary size limit warnings
        $bg = 'red' if $$lref < 10000 || $$lref > 20E6;
        $len_entry->configure(-disabledbackground => $bg);
        return;
    };
    my $auto_slice_end = sub {
        my $min = ${$self->text_variable_ref('slice_start')};
        my $max = ${$self->text_variable_ref('set_end')};
        my $len = ${$self->text_variable_ref('slice_len')};
        $len = $DEFAULT_SLICE_SIZE if $len < 10000;
        my $default = $min + $len - 1;
        $default = $max if $default > $max;
        $self->text_variable_ref('slice_end', $default, 1);
        $update_len->();
        return;
    };
    $slice_min_entry->bind('<FocusOut>', $auto_slice_end);

    my $max_label =
        $entry_frame->Label(
            -text => " end "
        )->pack(-side => 'left');
    $max_label->bind('<Destroy>' , sub { $self = undef }  );
    my $slice_max_entry =
        $entry_frame->Entry(
            -width        => 15,
            -relief       => 'sunken',
            -borderwidth  => 2,
            -textvariable => $self->text_variable_ref('slice_end'),
            #-font       =>   'Helvetica-14',   
        )->pack(
            -side => 'left', 
            -padx => 5,
            -fill => 'x',
        );
    $slice_max_entry->bind('<FocusOut>', $update_len);

    my $len_label =
      $len_frame->Label(-text => ' len ')->pack(-side => 'left');
    $len_entry =
      $len_frame->Entry
        (-width        => 15,
         -relief       => 'sunken',
         -borderwidth  => 2,
         -state        => 'disabled',
         -textvariable => $self->text_variable_ref('slice_len'),
        )->pack(-side => 'left', -padx => 5);
    $update_len->();

    $entry_frame->bind('<Destroy>' , sub { $self = undef }  );

    my $run_cancel_frame =
        $slice_window->Frame()->pack(
            -side => 'bottom', 
            -padx =>  5,
            -pady =>  5,
            -fill => 'x',
        );  
    my $runLace = $self->action('runLace');
    my $run_button =
        $run_cancel_frame->Button(
            -text    => 'Launch session',
            -command => [ $runLace, $self ],
        )->pack(-side => 'left');

    my $cancel_button =
        $run_cancel_frame->Button(
            -text    => 'Cancel',
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



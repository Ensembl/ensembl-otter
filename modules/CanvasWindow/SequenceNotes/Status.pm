=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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


### CanvasWindow::SequenceNotes::Status

package CanvasWindow::SequenceNotes::Status;

use strict;
use warnings;
use Carp;

use base 'CanvasWindow::SequenceNotes';

sub clone_index{
    my ($self, $index) = @_;

    if (defined $index) {
        $self->{'_clone_index'} = $index;


        # Disable Prev and Next buttons at ends of range
        my $cs_list = $self->get_CloneSequence_list();
        my $prev_button = $self->prev_button();
        my $next_button = $self->next_button();
        if ($index == 0) {
            # First clone
            $prev_button->configure(-state => 'disabled');
            $next_button->configure(-state => 'normal');
        }
        elsif ($index + 1 >= scalar(@$cs_list)) {
            # Last clone
            $prev_button->configure(-state => 'normal');
            $next_button->configure(-state => 'disabled');
        }
        else {
            # Internal clone
            $prev_button->configure(-state => 'normal');
            $next_button->configure(-state => 'normal');
        }
    }
    return $self->{'_clone_index'};
}

sub next_button {
    my ($self, $next) = @_;
    if ($next){
        $self->{'_next_button'} = $next;
    }
    return $self->{'_next_button'};
}
sub prev_button {
    my ($self, $prev) = @_;
    if ($prev){
        $self->{'_prev_button'} = $prev;
    }
    return $self->{'_prev_button'};
}

sub current_clone {
    my ($self, $clone) = @_;

    my $cs_list = $self->get_CloneSequence_list();
    my $i = $self->clone_index;
    my $cs = @$cs_list[$i];

    my $title = sprintf
      ('%sPipline Status of #%d  %s  (%s)',
       $Bio::Otter::Lace::Client::PFX,
        $i + 1,
        $cs->accession . '.' . $cs->sv,
        $cs->clone_name);
    $self->canvas->toplevel->title($title);
    return $cs;
}

sub initialise {
    my ($self) = @_;

    # Use a slightly smaller font so that more info fits on the screen
    $self->font_size(12);

    my $ss = $self->SequenceSet or confess "No SequenceSet or SequenceNotes attached";
    my $write = $ss->write_access;

    my $canvas = $self->canvas;
    my $top = $canvas->toplevel;

    my $button_frame = $top->Frame;
    $button_frame->pack(
        -side => 'top',
        );        

    ### These buttons should also highlight the current
    ### clone in the parent SequenceNotes window
    my $next_clone = sub { 
        my $cs_list = $self->get_CloneSequence_list(); 
        my $cur_idx = $self->clone_index();
        $self->clone_index(++$cur_idx) unless $cur_idx + 1 >= scalar(@$cs_list);
        $self->draw();
    };
    my $prev_clone = sub { 
        my $cs_list = $self->get_CloneSequence_list(); 
        my $cur_idx = $self->clone_index();
        $self->clone_index(--$cur_idx) if $cur_idx;
        $self->draw();
    };

    my $prev = $self->make_button($button_frame, 'Prev Clone', $prev_clone);
    my $next = $self->make_button($button_frame, 'Next Clone', $next_clone);
    $self->prev_button($prev);
    $self->next_button($next);

    $self->make_button($button_frame, 'Close', sub { $top->withdraw }, 0);

    # I think this is already bound..... 
    # It all gets cleared up twice with it.
    # And I think normal behaviour without it.
    $self->bind_close_window($top);

    # Define how the table gets drawn by supplying a column_methods array
    my $norm = $self->font_fixed;
    my $bold = $self->font_fixed_bold;   
    my $status_colors = {'completed'   => 'DarkGreen', 
                         'missing'     => 'red', 
                         'unavailable' => 'DarkRed'};
    my $column_write_text;
    {
        ## no critic (Variables::ProtectPrivateVars)
        $column_write_text = \&CanvasWindow::SequenceNotes::_column_write_text;
    }
    $self->column_methods(
        [
         [$column_write_text, sub{
             my $pipe_status = shift;
             return { -font => $norm, -tags => ['searchable'], -text => $pipe_status->{'name'} }; 
          }],
         [$column_write_text, sub{
             my $pipe_status = shift;
             my $status = $pipe_status->{'status'};
             return { -font => $norm, -tags => ['searchable'], -text => $status, -fill => $status_colors->{$status}};
          }],
         [$column_write_text, sub{
             my $pipe_status = shift;
             return { -font => $norm, -tags => ['searchable'], -text => $pipe_status->{'created'} };
          }],
         [$column_write_text, sub{
             my $pipe_status = shift;
             return { -font => $bold, -tags => ['searchable'], -text => $pipe_status->{'version'} };
          }],
        ]);

    $prev->bind('<Destroy>', sub { $self = undef });

    return $self;
}

sub get_rows_list {
    my ($self) = @_;         

    return $self->current_clone->pipelineStatus->display_list;
}

sub DESTROY {
    my ($self) = @_;
    my $idx = $self->clone_index();
    warn "Destroying CanvasWindow::SequenceNotes::Status with idx $idx\n";
    return;
}

1;

__END__

=head1 NAME - CanvasWindow::SequenceNotes::History

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


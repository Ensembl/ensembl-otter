=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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

package Tk::OrderedSelectionFrame;

# A Frame to perform ordered selection
#
# lg4

use Tk;

use base ('Tk::Frame');

Construct Tk::Widget 'OrderedSelectionFrame';

{ # scope for $bitmaps_defined

my $bitmaps_defined=0;

sub define_bitmaps {
	my $mw = shift @_;

	my @vert_arrow = (
		"............",
		"............",
		".....11.....",
		".....11.....",
		"....1111....",
		"....1111....",
		"...111111...",
		"...11..11...",
		"..111..111..",
		"..11....11..",
		".1111111111.",
		".1111111111.",
		"............",
		"............",
	);

	my @hor_arrows = (
		"...........................",
		".......111.......111.......",
		"......1111.......1111......",
		".....11111.......11111.....",
		"....111.11.......11.111....",
		"...111..11.......11..111...",
		"..111...11..111..11...111..",
	);
	push @hor_arrows, reverse @hor_arrows;


	$mw->DefineBitmap('moveup' => length($vert_arrow[0]), scalar(@vert_arrow),
		pack(("b".length($vert_arrow[0])) x scalar(@vert_arrow), @vert_arrow) );

	$mw->DefineBitmap('movedown' => length($vert_arrow[0]), scalar(@vert_arrow),
		pack(("b".length($vert_arrow[0])) x scalar(@vert_arrow), reverse @vert_arrow) );

	$mw->DefineBitmap('swap' => length($hor_arrows[0]), scalar(@hor_arrows),
		pack(("b".length($hor_arrows[0])) x scalar(@hor_arrows),
		# map { join('', reverse split(/(.)/,$_)); } @hor_arrows) );
		@hor_arrows) );
}

sub ClassInit {
	my ($class,$mw) = @_;
	$class->SUPER::ClassInit($mw);

	if(!$bitmaps_defined) {
		define_bitmaps($mw);
		$bitmaps_defined = 1;
	}
}

} # scope for $bitmaps_defined

sub Populate {
	my ($self,$args) = @_;

	$self->SUPER::Populate($args);

	$self->{_allwidgets} = $self->Frame()->pack('-side' => 'top', '-fill' => 'both', '-expand' => 1);


	$self->{_left_fr} = $self->{_allwidgets}->Frame()
		->pack('-side' => 'left', '-fill' => 'both', '-expand' => 1);
	$self->{_active_lab} = $self->{_left_fr}->Label('-text' => 'Active:')
		->pack('-side' => 'top');
	$self->{_active_lb}  = $self->{_left_fr}->Listbox('-selectmode' => 'browse')
		->pack('-side' => 'bottom', '-fill' => 'both', '-expand' => 1);

	$self->{_right_fr}      = $self->{_allwidgets}->Frame()
		->pack('-side' => 'right', '-fill' => 'both', '-expand' => 1);
	$self->{_remaining_lab} = $self->{_right_fr}->Label('-text' => 'Remaining:')
		->pack('-side' => 'top');
	$self->{_remaining_lb}  = $self->{_right_fr}->Listbox('-selectmode' => 'browse') # was => 'multiple'
		->pack('-side' => 'bottom', '-fill' => 'both', '-expand' => 1);

	tie @{$self->{active_aref}}, "Tk::Listbox", $self->{_active_lb};
	tie @{$self->{remaining_aref}}, "Tk::Listbox", $self->{_remaining_lb};

	$self->{_middle_fr}    = $self->{_allwidgets}->Frame()
		->pack('-side' => 'left', '-anchor' => 'center');
	$self->{_moveup_btn}   = $self->{_middle_fr}->Button(
			'-bitmap' => 'moveup',
			'-command' => sub{
				my $cur_sel_index = ($self->{_active_lb}->curselection())[0];
				if( defined($cur_sel_index)
				and $cur_sel_index>0 ) {
					$self->updown_active($cur_sel_index,$cur_sel_index-1);
				}
			}
		)->pack('-fill' => 'x', '-side' => 'top');
	$self->{_movedown_btn} = $self->{_middle_fr}->Button(
			'-bitmap' => 'movedown',
			'-command' => sub{
				my $cur_sel_index = ($self->{_active_lb}->curselection())[0];
				if( defined($cur_sel_index)
				and $cur_sel_index+1<scalar(@{$self->{active_aref}}) ) {
					$self->updown_active($cur_sel_index+1,$cur_sel_index+1);
				}
			}
		)->pack('-fill' => 'x', '-side' => 'top');
	$self->{_make_active}  = $self->{_middle_fr}->Button(
			'-bitmap' => 'swap',
			'-command' => sub{
				if(my @d_selection = $self->{_active_lb}->curselection() ) {
					$self->deactivate_entries(@d_selection);
				} elsif(my @a_selection = $self->{_remaining_lb}->curselection() ) {
					$self->activate_entries(@a_selection);
				}
			}
		)->pack('-fill' => 'x', '-side' => 'top');

}

sub _transfer {		# NB: not an instance method
	my ($from_ref,$to_ref,@selected) = @_;

	my @remove = reverse sort @selected;

	push @$to_ref, @$from_ref[@selected];
	delete @$from_ref[@remove];
}


	# The following methods are provided to be _extended_ (not just overridden)
	# by subclasses to maintain ordering in the parralel arrays of objects:

sub updown_active {
	my ($self,$high_index,$new_sel_index) = @_;

	my $low_index = $high_index-1;

		# swap high<->low
	($self->{active_aref}->[$low_index], $self->{active_aref}->[$high_index]) =
		($self->{active_aref}->[$high_index], $self->{active_aref}->[$low_index]);

		# select the one to be selected
	$self->{_active_lb}->selectionSet($new_sel_index);
}

sub activate_entries {	# transfer them to the end of the left list
	my ($self,@selected) = @_;

	my $new_sel_index = scalar(@{$self->{active_aref}});

	_transfer($self->{remaining_aref},$self->{active_aref},@selected);

	$self->{_active_lb}->selectionSet($new_sel_index);
}

sub deactivate_entries {# transfer them to the end of the right list
	my ($self,@selected) = @_;

	my $new_sel_index = scalar(@{$self->{remaining_aref}});

	_transfer($self->{active_aref},$self->{remaining_aref},@selected);

	$self->{_remaining_lb}->selectionSet($new_sel_index);
}

sub add_entries {
	my $self = shift @_;

	push @{$self->{remaining_aref}}, @_;
}

sub set_remaining_entries { # entries are passed inside and copied into the tied array
	my $self = shift @_;

	@{$self->{remaining_aref}} = @_; # NB: the tied reference must stay the same
}

sub change_active_entry {
	my ($self,$ind,$entry) = @_;

	$self->{active_aref}->[$ind] = $entry;

	$self->{_active_lb}->selectionSet($ind);
}

sub set_active_entries { # entries are passed inside and copied into the tied array
	my $self = shift @_;

	@{$self->{active_aref}} = @_; # NB: the tied reference must stay the same
}

sub release { # the Black Spot
        my $self = shift @_;
                                                                                                            
        for my $k (keys %$self) {
                delete $self->{$k};
        }
}

1;


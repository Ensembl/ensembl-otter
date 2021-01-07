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


### Tk::ComboBox

package Tk::ComboBox;

use strict;

use vars qw($VERSION);
$VERSION = '0.1';

use Tk qw(Ev);
use Carp;
use strict;

require Tk::Frame;
require Tk::LabEntry;

use base qw(Tk::Frame);
Construct Tk::Widget 'ComboBox';

sub Populate {
    my ($w, $args) = @_;

    $w->SUPER::Populate($args);

    # entry widget and arrow button
    my $lpack = delete $args->{-labelPack};
    if (not defined $lpack) {
	$lpack = [-side => 'left', -anchor => 'e'];
    }
    my $var = "";
    my $e = $w->LabEntry(-labelPack => $lpack,
			 -label => delete $args->{-label},
			 -textvariable => \$var,);
    my $b = $w->Button(-bitmap => '@' . Tk->findINC('cbxarrow.xbm'));
    $w->Advertise('entry' => $e);
    $w->Advertise('arrow' => $b);
    $b->pack(-side => 'right', -padx => 1, -fill => 'y', -expand => 1);
    $e->pack(-side => 'right', -fill => 'x', -expand => 1, -padx => 1);

    # popup shell for listbox with values.
    my $c = $w->Toplevel(-borderwidth => 0, -relief => 'flat');
    $c->overrideredirect(1);
    $c->withdraw;
    my $sl = $c->Scrolled( qw/Listbox -selectmode browse -scrollbars oe/ );
    $w->Advertise('choices' => $c);
    $w->Advertise('slistbox' => $sl);
    $sl->pack(-expand => 1, -fill => 'both');

    # other initializations
    $w->SetBindings;
    $w->{'popped'} = 0;
    $w->Delegates('insert' => $sl, 'delete' => $sl, get => $sl, DEFAULT => $e);
    
    my $ent = $e->Subwidget('entry');
    
    my $default_config_widgets = [
        $e->Subwidget('entry'),
        $sl->Subwidget('listbox'),
        ];
    
    $w->ConfigSpecs(
        -listwidth   => [qw/PASSIVE  listWidth   ListWidth/,   undef],
        -listheight  => [qw/PASSIVE  listHeight  ListHeight/,   undef],
        -listcmd     => [qw/CALLBACK listCmd     ListCmd/,     undef],
        -browsecmd   => [qw/CALLBACK browseCmd   BrowseCmd/,   undef],
        -choices     => [qw/METHOD   choices     Choices/,     undef],
        -state       => [qw/METHOD   state       State         normal/],
        -arrowimage  => [ {-image => $b}, qw/arrowImage ArrowImage/, undef],
        -variable    => '-textvariable',
	    -colorstate  => [qw/PASSIVE  colorState  ColorState/,  undef],
        -command     => '-browsecmd',
        -options     => '-choices',
        'DEFAULT'    => [$e],
        -relief      => [[$e, $c], qw{ relief Relief }, 'sunken'],
        -background         => [$default_config_widgets, qw{       background Background }, undef],
        -foreground         => [$default_config_widgets, qw{       foreground Foreground }, undef],
        -selectforeground   => [$default_config_widgets, qw{ selectForeground Background }, undef],
        -selectbackground   => [$default_config_widgets, qw{ selectBackground Foreground }, undef],
        -font        => [$default_config_widgets, qw{ font Font }, undef],
        );
}

sub SetBindings {
    my ($w) = @_;

    my $e = $w->Subwidget('entry');
    my $b = $w->Subwidget('arrow');

    # set bind tags
    $w->bindtags([$w, 'Tk::ComboBox', $w->toplevel, 'all']);
    $e->bindtags([$e, $e->toplevel, 'all']);

    # Unbind all Button class bindings from this button
    $b->bindtags(undef);

    # Re-establish standard Button highlighting behaviour
    $b->bind('<Leave>', sub{
        if ($w->cget('-state') ne 'disabled') {
          $b->configure('-state' => 'normal');
        }
      });
    $b->bind('<Enter>', sub{
        if ($w->cget('-state') ne 'disabled') {
          $b->configure('-state' => 'active');
        }
      });

    # bindings for the button and entry
    foreach my $event (qw{ <ButtonPress-1> <space> <Return> }) {
        $b->bind($event, [$w,'BtnDown']);
    }
    #$b->bind('<space>',[$w,'space']);

    # bindings for listbox
    my $sl = $w->Subwidget('slistbox');
    my $l = $sl->Subwidget('listbox');
    $l->bind('<ButtonRelease-1>',[$w,'ListboxRelease',Ev('x'),Ev('y')]);
    $l->bind('<Escape>' => [$w,'LbClose']);
    $l->bind('<Return>' => [$w,'Return',$l]);

    # allow click outside the popped up listbox to pop it down.
    $w->bind('<1>','BtnDown');
}

sub space {
 my $w = shift;
 $w->BtnDown;
 $w->{'savefocus'} = $w->focusCurrent;
 $w->Subwidget('slistbox')->focus;
}


sub ListboxRelease {
 my ($w,$x,$y) = @_;
 $w->LbChoose($x, $y);
}

sub Return {
 my ($w,$l) = @_;
 my($x, $y) = $l->bbox($l->curselection);
 $w->LbChoose($x, $y)
}


sub BtnDown {
    my ($w) = @_;
    return if $w->cget( '-state' ) eq 'disabled';

    if ($w->{'popped'}) {
	$w->Popdown;
    } else {
	$w->PopupChoices;
    }
}

sub PopupChoices {
    my ($w) = @_;

    if (!$w->{'popped'}) {
	my $e = $w->Subwidget('entry')->Subwidget('entry');
	my $c = $w->Subwidget('choices');
	my $s = $w->Subwidget('slistbox');
	my $a = $w->Subwidget('arrow');
        $a->butDown;
        $w->Callback(-listcmd => $w);
	my $y1 = $e->rooty + $e->height;
	my $bd = $c->cget(-bd) + $c->cget(-highlightthickness);
	my $x1 = $e->rootx;
	my ($width, $x2);
	if (defined $w->cget(-listwidth)) {
	    $width = $w->cget(-listwidth);
	    $x2 = $x1 + $width;
	} else {
	    $x2 = $a->rootx + $a->width;
	    $width = $x2 - $x1;
	}
        
        my $choice_count = $s->size;
        my $max_size = $w->cget(-listheight) || 20;
        if ($choice_count > $max_size) {
            $choice_count = $max_size;
        }
        #$s->configure(-height => $choice_count);

        my $font = $w->cget('-font');
        my $linesp = 3 + $w->fontMetrics($font, '-linespace');
	my $height = 4 + ($linesp * $choice_count) + (2 * $bd);
        
	# if listbox is too far right, pull it back to the left
	#
	if ($x2 > $w->vrootwidth) {
	    $x1 = $w->vrootwidth - $width;
	}

	# if listbox is too far left, pull it back to the right
	#
	if ($x1 < 0) {
	    $x1 = 0;
	}

	# if listbox is below bottom of screen, pull it up.
	my $y2 = $y1 + $height;
	if ($y2 > $w->vrootheight) {
	    $y1 = $e->rooty - ($height + ($bd * 2)) - 1;
	}

	$c->geometry(sprintf('%dx%d+%d+%d', $width, $height, $x1, $y1));
	$c->deiconify;
	$c->raise;
	$e->focus;
	$w->{'popped'} = 1;

	$c->configure(-cursor => 'arrow');
	$w->grabGlobal;
    }
}

# choose value from listbox if appropriate
sub LbChoose {
    my ($w, $x, $y) = @_;
    my $l = $w->Subwidget('slistbox')->Subwidget('listbox');
    if ((($x < 0) || ($x > $l->Width)) || (($y < 0) || ($y > $l->Height))) {
	    # mouse was clicked outside the listbox... close the listbox
	    $w->LbClose;
        #warn "Click outside listbox";
    } else {
	    # select appropriate entry and close the listbox
	    $w->LbCopySelection;
        $w->Callback(-browsecmd => $w, $w->Subwidget('entry')->get);
    }
}

# close the listbox after clearing selection
sub LbClose {
    my ($w) = @_;
    my $l = $w->Subwidget('slistbox')->Subwidget('listbox');
    $l->selection('clear', 0, 'end');
    $w->Popdown;
}

# copy the selection to the entry and close listbox
sub LbCopySelection {
    my ($w) = @_;
    my $index = $w->LbIndex;
    if (defined $index) {
	    $w->{'curIndex'} = $index;
	    my $l = $w->Subwidget('slistbox')->Subwidget('listbox');
        my $var_ref = $w->cget( '-textvariable' );
        my $value = $l->get($index);
        #warn "Got value '$value' at position '$index'";
        $$var_ref = $value;
        #$$var_ref = $l->get($index);
    }
    $w->Popdown;
}

sub LbIndex {
    my ($w, $flag) = @_;
    my $sel = $w->Subwidget('slistbox')->Subwidget('listbox')->curselection;
    if (defined $sel) {
        ### This was broken somehow
        if (ref($sel) eq 'ARRAY') {
            return $sel->[0];
        } else {
	        warn "Unexpected return type from Tk::Listbox->curselection : '$sel'";
            return $sel;
        }
    } else {
	    if (defined $flag && ($flag eq 'emptyOK')) {
	        return undef;
	    } else {
	        return 0;
	    }
    }
}

# remove the listbox
sub Popdown {
    my ($w) = @_;
    if ($w->{'savefocus'} && Tk::Exists($w->{'savefocus'})) {
	$w->{'savefocus'}->focus;
	delete $w->{'savefocus'};
    }
    if ($w->{'popped'}) {
	my $c = $w->Subwidget('choices');
	$c->withdraw;
	$w->grabRelease;
	$w->{'popped'} = 0;
        $w->Subwidget('arrow')->butUp;
    }
}

sub choices {
 my ($w,$choices) = @_;
 if (@_ > 1)
  {
   $w->delete( qw/0 end/ );
   ### Code commented out puts the first choice
   ### into the Entry widget if there are choices
   ### and the Entry is empty.
   #my $var = $w->cget('-textvariable');
   #my $old = $$var;
   #my( %seen );
   foreach my $val (@$choices)
    {
     $w->insert( 'end', $val);
     #$seen{$val} = 1;
    }
    #unless (defined($old) and defined $seen{$old}) {
    #    $old = @$choices ? $choices->[0] : undef;
    #}
    #$$var = $old;
  }
 else
  {
   return( $w->get( qw/0 end/ ) );
  }
}

sub _set_edit_state {
    my( $w, $state ) = @_;

    my $entry  = $w->Subwidget( 'entry' );
    my $button = $w->Subwidget( 'arrow' );

    if ($w->cget( '-colorstate' )) {
	my $color;
	if( $state eq 'normal' ) {                  # Editable
	    $color = 'gray95';
	} else {                                    # Not Editable
	    $color = $w->cget( -background ) || 'lightgray';
	}
	$entry->Subwidget( 'entry' )->configure( -background => $color );
    }

    if( $state eq 'readonly' ) {
        $entry->configure( -state => 'disabled' );
        $button->configure( -state => 'normal' );
    } else {
        $entry->configure( -state => $state );
        $button->configure( -state => $state );
    }
}

sub state {
    my $w = shift;
    unless( @_ ) {
        return( $w->{Configure}{-state} );
    } else {
        my $state = shift;
        $w->{Configure}{-state} = $state;
        $w->_set_edit_state( $state );
    }
}

sub _max {
    my $max = shift;
    foreach my $val (@_) {
        $max = $val if $max < $val;
    }
    return( $max );
}

sub shrinkwrap {
    my( $w, $size ) = @_;

    unless( defined $size ) {
        $size = _max( map( length, $w->get( qw/0 end/ ) ) ) || 0;;
    }

    my $lb = $w->Subwidget( 'slistbox' )->Subwidget( 'listbox' );
    $w->configure(  -width => $size );
    $lb->configure( -width => $size );
}



1;

__END__

=head1 NAME - Tk::ComboBox

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


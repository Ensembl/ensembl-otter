package EditWindow::Preferences;

use strict;
use warnings;
use Carp;

require Tk::Pane;
require Tk::Font;
use base 'EditWindow';


sub initialise {
    my ($self) = @_;
    my $top = $self->top;
    $top->configure(-borderwidth => 0, -highlightthickness => 0);

    # Status & info
    my $bf = $top->Frame(-relief => 'sunken', -borderwidth => 2);
    $self->bot_frame($bf);

## packing it empty breaks (=0,0) initial window size
#    $bf->pack(-side => 'bottom', -fill => 'x');
#    $bf->Label(-bg => 'white', -text => 'some info here')->pack;

    # Options frame
    my $sf = $top->Scrolled(Pane => -borderwidth => 3, -relief => 'sunken',
                            -scrollbars => 'osoe', -sticky => 'nsew');
    $sf->pack(-side => 'top', -fill => 'both', -expand => 1);
    my $f = $sf->Subwidget('scrolled');
    foreach my $w (map { $sf->Subwidget($_) } qw( xscrollbar yscrollbar )) {
        $w->configure(-takefocus => 0); # don't tab into scrollbars
    }
    $self->opt_frame($f);

    $self->opt_head('Basic information');
    $self->opt_add(author => 'Author email', 'Entry');
    $self->opt_add(write_access => 'Request write access', 'Checkbutton');

    $self->opt_head('Fancy stuff');

    $self->opts_done;

    $top->bind('<Destroy>', sub{ $self = undef; });
## not working usefully
# $self->set_minsize;

    return ();
}



sub Client {
    my ($self, @set) = shift;
    ($self->{_client}) = @set if @set;
    return $self->{_client};
}

sub opt_frame {
    my $self = shift;
    ($self->{_optframe}) = @_ if @_;
    return $self->{_optframe};
}

sub bot_frame {
    my $self = shift;
    ($self->{_botframe}) = @_ if @_;
    return $self->{_botframe};
}



sub font {
    my ($self, $which) = @_;
    my $font =
      { head => [qw[ Helvetica 20 bold ]],
        opt => [qw[ Helvetica 14 normal ]],
        entry => [qw[ Courier 16 normal ]] }->{$which};
    confess "bad font '$which'" unless $font;
    return $font;
}

sub opt_head {
    my ($self, $label) = @_;
    my $f = $self->opt_frame;
    my (undef, $r) = $f->gridSize;

    # gap above
    $f->gridRowconfigure($r++, -minsize => 14) if $r;

    my $l = $f->Label(-text => $label, -font => $self->font('head'));
    $l->grid(-row => $r, -column => 0, -columnspan => 2);

    # <hr/>
    $f->Frame(-bg => 'black', -height => 1, -highlightthickness => 0)->
      grid(-row => $r+1, -column => 0, -columnspan => 3, -sticky => 'ew');

    return ();
}

sub opt_add {
    my ($self, $method, $label, $type) = @_;
    my $f = $self->opt_frame;
    my (undef, $rows) = $f->gridSize;

    $f->Label(-text => $label, -font => $self->font('opt'))
      ->grid(-row => $rows, -column => 0, -sticky => 'w');

    my $w = $f->$type();
    $w->grid(-row => $rows, -column => 1, -sticky => 'ew');

    if ($type eq 'Entry') {
        $w->configure(-font => $self->font('entry'));
    }

    return;
}

sub opts_done {
    my ($self) = @_;
    my $f = $self->opt_frame;
    my (undef, $r) = $f->gridSize;

    # last column & extra row at bottom can expand
    $f->gridRowconfigure($r,   -minsize => 0, -weight => 1);
    $f->gridColumnconfigure(2, -minsize => 0, -weight => 1);

    return ();
}

sub DESTROY {
    my ($self) = @_;

    warn "Destroying a '", ref($self), "'";

    return;
}

1;

__END__

=head1 NAME - EditWindow::Preferences

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


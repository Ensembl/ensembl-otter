package EditWindow::Preferences;

use strict;
use warnings;
use Carp;


require Tk::Pane;
require Tk::Dialog;
use base 'EditWindow';

use Try::Tiny;
use Bio::Otter::Lace::Defaults;


sub initialise {
    my ($self) = @_;
    my $top = $self->top;
    $self->_mkframes;

    $self->opt_head('Basic information');
    $self->opt_add
      (author => 'Author email', 'Entry',
       'The email address with which you identify yourself to the Otter Server.');
    $self->opt_add
      (write_access => 'Request write access', 'Checkbutton',
       'When this is off, Otterlace will not ask to save your changes to the Otter Server.');

    $self->_opts_done;
    $self->_size_fix;
    $self->_reset;

    $top->bind('<Destroy>', sub{ $self = undef; });

    return ();
}


sub _size_fix {
    my ($self) = @_;
    my $top = $self->top;
    my $f = $self->opt_frame;

    $top->update;

    # $top->reqwidth,reqheight calculation broken by use of Scrolled,
    # do it manually
    my @b = $f->gridBbox;
    my $w = $b[2] - $b[0];
    my $h = $b[3] - $b[1];
    $w += $top->width - $f->width;
    $h += $top->height - $f->height;

    # ensure scrollbars (in bistable) initial state = off
    $h += $self->widg('optsf')->Subwidget('xscrollbar')->height;

    $top->maxsize($w, $h);
    $top->configure(-width => $w, -height => $h);
    return ($w, $h);
}



sub Client {
    my ($self, @set) = shift;
    ($self->{_client}) = @set if @set;
    return $self->{_client};
}

sub opt_frame {
    my $self = shift;
    return $self->widg('optsf.pane');
}

sub widg {
    my ($self, $widg_path) = @_;
    my $top_path = $self->top->PathName; # name changes per toplevel instance
    my $widg = $self->top->Widget("$top_path.$widg_path");
    confess "Bad Widget PathName $top_path.$widg_path" unless $widg;
    return $widg;
}


sub font {
    my ($self, $which) = @_;
    my $font =
      { head => [qw[ Helvetica 20 bold ]],
        opt => [qw[ Helvetica 14 normal ]],
        help => [qw[ Helvetica 14 normal ]],
        entry => [qw[ Courier 16 normal ]] }->{$which};
    confess "bad font '$which'" unless $font;
    return $font;
}


# opt_frame.(widget).grid has this layout
#
# 0(fixed)    1(fixed)   2(grows)
# <---- header text --->
# <------ header underline ----->
# < label >   < widget >
#             <--- help text --->

sub opt_head {
    my ($self, $label) = @_;
    my $f = $self->opt_frame;
    my (undef, $r) = $f->gridSize;

    # gap above
    $f->gridRowconfigure($r++, -minsize => 14) if $r;

    my $l = $f->Label(-text => $label, -font => $self->font('head'));
    $l->grid(-row => $r, -column => 0, -columnspan => 2, -pady => 8);

    # <hr/>
    $f->Frame(-bg => 'black', -height => 1)->
      grid(-row => $r+1, -column => 0, -columnspan => 3, -sticky => 'ew');

    return ();
}

sub opt_add {
    my ($self, $cfg, $label, $type, $help) = @_;
    my $f = $self->opt_frame;
    my (undef, $rows) = $f->gridSize;

    $f->Label(-text => $label, -font => $self->font('opt'))
      ->grid(-row => $rows, -column => 0,
             -sticky => 'w', -pady => 4);

    my $w = $f->$type();
    $w->grid(-row => $rows, -column => 1,
             -sticky => 'ew', -pady => 4, -padx => 4);

    my $st_w = $f->Label(-text => '');
    $st_w->grid(-row => $rows, -column => 2, -sticky => 'w');

    $f->Label(-text => $help, -font => $self->font('help'),
              -wraplength => 420, -justify => 'left')
      ->grid(-row => $rows+1, -column => 1, -columnspan => 2,
             -sticky => 'w', -padx => 4);

    $f->gridRowconfigure($rows+2, -minsize => 8); # gap

    my $chk = [ $self => _check_state => $cfg ];
    my $var;
    $self->{_widg}{$cfg} = { entry => $w,
                             status => $st_w,
                             var => \$var,
                             type => $type };

    if ($type eq 'Entry') {
        $w->configure(-font => $self->font('entry'),
                      -textvariable => \$var,
                      -validatecommand => sub { $w->afterIdle($chk); return 1 },
                      -validate => 'all');
    } elsif ($type eq 'Checkbutton') {
        $w->configure(-variable => \$var,
                      -command => $chk);
    } else {
        die "Cannot opt_add type=$type for $cfg";
    }

    return;
}

sub _get_state {
    my ($self, $cfg) = @_;
    my $type = $self->{_widg}{$cfg}{type};
    my $txt = $self->Client->$cfg;
    $txt = $txt ? 1 : 0 if $type eq 'Checkbutton';
    return $txt;
}

sub _check_state {
    my ($self, $cfg) = @_;
    my $var_ref = $self->{_widg}{$cfg}{var};
    my $set = $self->_get_state($cfg);
    my $S = $self->{_widg}{$cfg}{status};
    if ($set eq $$var_ref) {
        $S->configure(-text => 'unchanged', -fg => 'darkgreen');
        return 0;
    } else {
        $S->configure(-text => 'ready to save', -fg => 'red');
        return 1;
    }
}


sub _mkframes {
    my ($self) = @_;
    my $top = $self->top;
    $top->gridRowconfigure(0, -weight => 1);
    $top->gridColumnconfigure(0, -weight => 1);

    # Options pane at top
    my $sf = $top->Scrolled(Pane => Name => 'optsf',
                            -scrollbars => 'osoe', -sticky => 'nsew');
    $sf->grid(-column => 0, -row => 0, -sticky => 'nsew');
    foreach my $w (map { $sf->Subwidget($_) } qw( xscrollbar yscrollbar )) {
        $w->configure(-takefocus => 0); # don't tab into scrollbars
    }
    my $f = $sf->Subwidget('scrolled');

    # Control buttons at bottom
    my $bf = $top->Frame(Name => 'botf');
    $bf->grid(-column => 0, -row => 1, -sticky => 'nsew');

    my @but = ($bf->Button(Name => 'close', -text => 'Close'),
               $bf->Button(Name => 'reset', -text => 'Reset'),
               $bf->Button(Name => 'save', -text => 'Save'));

    for (my $i=0; $i<@but; $i++) {
        my $B = $but[$i];
        my $k = substr($B->name, 0, 1);
        $B->configure(-underline => 0);
        $B->grid(-sticky => 'nsew', -row => 0, -column => $i);
        $B->configure(-command => [ $self, '_'.$B->name ]);
        $top->bind("<Alt-$k>", [ $B => 'invoke' ]);
    }

    return ();
}

sub _opts_done {
    my ($self) = @_;
    my $f = $self->opt_frame;
    my (undef, $r) = $f->gridSize;

    # last column & extra row at bottom can expand
    $f->gridRowconfigure($r,   -minsize => 0, -weight => 1);
    $f->gridColumnconfigure(2, -minsize => 0, -weight => 1);

    return ();
}


sub _reset { # button
    my ($self) = @_;
    foreach my $cfg (keys %{ $self->{_widg} }) {
        my $var_ref = $self->{_widg}{$cfg}{var};
        $$var_ref = $self->_get_state($cfg);
        $self->_check_state($cfg);
    }
    return ();
}

sub _close {
    my ($self) = @_;
    return $self->top->destroy;
}

sub _save { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my ($cfg, $S);
    return try {
        while (($cfg, my $v) = each %{ $self->{_widg} }) {
            next unless $self->_check_state($cfg);
            my $var_ref = $v->{var};
            $S = $v->{status};
            Bio::Otter::Lace::Defaults::set_and_save('client', $cfg, $$var_ref);
            $S->configure(-text => 'saved', -fg => 'darkgreen');
        }
        1;
    } catch {
        $cfg = '(nil)' unless defined $cfg;
        $S->configure(-text => "save failed", -fg => 'red') if $S;
        warn "Preference save for '$cfg' failed: $_";
        $self->_error
          ("Unable to overwrite preferences file due to changes from another application.\n
Please restart Otterlace if you need to make changes.\n
Details are in the Error Log.");
        0;
    };
}

sub _error {
    my ($self, $txt) = @_;
    my $err = $self->top->Dialog
      (-title => $Bio::Otter::Lace::Client::PFX.'Preferences save failed',
       -bitmap => 'warning',
       -text => $txt,
       -buttons => [ 'OK' ]);
    $err->Show;
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


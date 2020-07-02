=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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

package EditWindow::Preferences;

use strict;
use warnings;
use Carp;


require Tk::Pane;
require Tk::Dialog;
use base 'EditWindow';

use Try::Tiny;
use POSIX ();

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
       'When this is off, Otter will not ask to save your changes to the Otter Server.');

    if ($self->Client->no_user_config) {
        $self->opt_banner
          ("Please check and 'Save' your settings which will create the ".
           "configuration file and authenticate you.  Then 'Close' this window.");
    } else {
        # TEMPORARY
        $self->opt_banner
          ("Sorry, Otter is not ready for established users to reconfigure ".
           "it while it is running.  You may edit the configuration file ".
           "directly, and changes will take effect after you restart the ".
           "application.  On the Mac the 'Edit directly' button helps with this.");
        foreach my $cfg (qw( author write_access )) {
            my $e = $self->{_widg}{$cfg}{entry};
            $e->configure(-state => 'disabled');
        }
    }

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
    $top->geometry("${w}x${h}");

    return ($w, $h);
}



sub Client {
    my ($self, @set) = @_;
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

    my $l = $f->Label(-text => $label, -font => $self->named_font('head1'));
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

    my $f_prop = $self->named_font('prop');

    $f->Label(-text => $label, -font => $f_prop)
      ->grid(-row => $rows, -column => 0,
             -sticky => 'w', -pady => 4);

    my $w = $f->$type();
    $w->grid(-row => $rows, -column => 1,
             -sticky => 'ew', -pady => 4, -padx => 4);

    my $st_w = $f->Label(-text => '', -font => $f_prop);
    $st_w->grid(-row => $rows, -column => 2, -sticky => 'w');

    $f->Label(-text => $help, -font => $f_prop,
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
        $w->configure(-font => $self->named_font('mono'),
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
               $bf->Button(Name => 'edit', -text => 'Edit directly'),
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

sub opt_banner {
    my ($self, $msg) = @_;
    my $f = $self->opt_frame;
    my (undef, $r) = $f->gridSize;
    $f->Label(-text => $msg,
              -wraplength => 500,
              -justify => 'left',
              -font => $self->named_font('prop'),
             )->grid(-row => $r, -column => 0, -columnspan => 3,
                     -pady => 12, -sticky => 'nsew');
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


sub _button_state {
    my ($self) = @_;

    my $absent = $self->Client->no_user_config;
    my $can_edit = $self->_edit_cmd && !$absent;

    $self->widg('botf.edit')->configure(-state => $can_edit ? 'normal' : 'disabled');

    # when there is no config file, we need a save
    $self->widg('botf.close')->configure(-state => $absent ? 'disabled' : 'normal');

    return ();
}

sub _reset { # button
    my ($self) = @_;
    foreach my $cfg (keys %{ $self->{_widg} }) {
        my $var_ref = $self->{_widg}{$cfg}{var};
        $$var_ref = $self->_get_state($cfg);
        $self->_check_state($cfg);
    }
    $self->_button_state;
    return ();
}

sub _close {
    my ($self) = @_;
    return $self->top->destroy;
}

sub _save { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $need_save = $self->Client->no_user_config;
    my ($cfg, $S);
    return try {
        while (($cfg, my $v) = each %{ $self->{_widg} }) {
            if ($need_save && $cfg eq 'author') {
                # save, even if it matches the default
            } elsif (!$self->_check_state($cfg)) {
                # nothing to do
                next;
            }
            my $var_ref = $v->{var};
            $S = $v->{status};
            $self->Client->config_set('client', $cfg, $$var_ref);
            $S->configure(-text => 'saved', -fg => 'darkgreen');
            $self->_button_state;
        }
        1;
    } catch {
        $cfg = '(nil)' unless defined $cfg;
        $S->configure(-text => "save failed", -fg => 'red') if $S;
        warn "Preference save for '$cfg' failed: $_";
        $self->_error
          ("Unable to overwrite preferences file due to changes from another application.\n
Please restart Otter if you need to make changes.\n
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

sub _edit { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my @cmd = $self->_edit_cmd;
    push @cmd, Bio::Otter::Lace::Defaults::user_config_filename();

    # Run in the background.  For Mac 'open', this is superfluous.
    # For gedit it is necessary, this way or system("@cmd &")
    my $pid = fork();
    if (!defined $pid) {
        die "Could not edit, fork failed $!"; # will be a background Tk error
    } elsif ($pid) {
        warn "Ran '@cmd', pid=$pid\n";
        # (No UI error if it fails)
    } else {
        { exec(@cmd); }
        try {
            warn "Failed to exec '@cmd': $!";
            close STDERR;
            close STDOUT;
        }; # no catch, just be sure to _exit
        POSIX::_exit(127); # avoid triggering DESTROY
    }
    $self->_close;
    return ();
}

sub _edit_cmd {
    my ($self) = @_;
    return qw( open -e ) if $^O eq 'darwin';
# xdg-open won't edit my config.ini
    foreach my $bin (qw( /usr/bin/gedit /usr/bin/nedit )) {
        return $bin if -x $bin && -r _;
    }
    warn "I can find no editor here";
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


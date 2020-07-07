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

package Tk::Screens;

use strict;
use warnings;
use Try::Tiny;


sub nxt {
    my ($class, $widget) = @_;

    # Cache the "next" screen on MainWindow
    my $mw = $widget->Widget(".");
    my $dpys = $mw->{_Tk_Screens_all} ||= $class->_probe_screens($mw);

    my $next = $dpys->[0];
    return $next;
}


sub _new {
    my ($class, $display_name, $screen_num) = @_;
    my $self = bless { name => $display_name, i => $screen_num }, $class;
    return $self;
}

# Like ":10.1" and always meaningful.
sub name {
    my ($self) = @_;
    return $self->{name};
}

# Screen number (optional)
sub i {
    my ($self) = @_;
    return $self->{i};
}

# Call in list context.  If we have a choice, returns "--screen=<num>"
# else returns empty list.
sub gtk_arg {
    my ($self) = @_;
    die "wantarray" unless wantarray;

    my $i = $self->i;
    if (defined $i) {
        return ("--screen=$i");
    } else {
        return ();
    }
}


# Tk advertises no method to discover other screens, but we can ask
sub _probe_screens {
    my ($class, $mw) = @_;
    my $current = $mw->screen;
    my ($display, $screen) = $current =~ m{^(.*:\d+)\.(\d+)$};

    if (!defined $display) {
        warn "Failed to parse screen name '$current', assuming one screen";
        return [ $class->_new($current) ];
    } else {
        my @dpy;
        for (my $i=0; $i <= 255; $i++) {
            last unless
              try {
                  my $name = "$display.$i";
                  my $tl = $mw->Toplevel(-screen => $name);
                  # still here - success
                  $dpy[$i] = $class->_new($name, $i);
                  $tl->destroy;
                  1;
              } catch {
                  warn "Unexpected error in _probe_screens: $_"
                    unless m{couldn't connect to display|bad screen number};
                  0;
              };
        }

        if (1 == @dpy) {
            # One screen, for which we understand the name.
            # There is no point specifying what to use.
            return [ $class->_new($current) ];
        } else {
            # Rotate them to start from 1+$screen,
            # so that $dpy[0] is the "next" one
            push @dpy, splice(@dpy, 0, 1+$screen);
            return \@dpy;
        }
    }
}

1;

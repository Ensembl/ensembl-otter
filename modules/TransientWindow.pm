=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


### TransientWindow

package TransientWindow;

use strict;
use warnings;
use Carp;

sub new {
    my ($cls, $tk, $title) = @_;
    unless ($tk) {
        confess "need a Tk";
    }
    my $self = bless {}, ref($cls) || $cls;

    $self->title($title);
    my $window = $tk->Toplevel(-title => $title)
      || print STDOUT "didn't return window?";
    $window->transient($tk);
    $self->window($window);
    $self->hide_me();

    return $self;
}

sub initialise {
    my ($self) = @_;
    my $window = $self->window();
    $window->protocol('WM_DELETE_WINDOW', $self->hide_me_ref());
    $window->bind('<Destroy>', sub { $self = undef });
    return;
}

sub draw {
    my ($self) = @_;
    $self->show_me();
    return;
}

sub hide_me_ref {
    my ($self) = @_;
    my $ref  = $self->{'_hide_the_window'};
    unless ($ref) {
        my $window = $self->window();
        $self->{'_hide_the_window'} = $ref = sub { $window->withdraw(); };
    }
    return $ref;
}

sub hide_me {
    my ($self) = @_;
    $self->hide_me_ref->();
    return;
}

sub show_me_ref {
    my ($self) = @_;
    my $ref = $self->{'_show_the_window'};
    unless ($ref) {
        my $win = $self->window();
        $self->{'_show_the_window'} = $ref = sub {
            $win->deiconify;
            $win->raise;
            $win->focus;
        };
    }
    return $ref;
}

sub show_me {
    my ($self) = @_;
    $self->show_me_ref->();
    return;
}

sub window {
    my ($self, $win) = @_;
    if ($win) {
        $self->{'_window'} = $win;
    }
    return $self->{'_window'};
}

# XXX:DUP copy, awaiting inheritance from BaseWindow
sub balloon {
    my ($self) = @_;

    $self->{'_balloon'} ||= $self->window->Balloon(
        -state  => 'balloon',
        );
    return $self->{'_balloon'};
}

sub title {
    my ($self, $title) = @_;
    $self->{'_win_title'} = $title if $title;
    return $self->{'_win_title'} || __PACKAGE__;
}

sub text_variable_ref {
    my ($self, $named, $default, $initialise) = @_;
    return unless $named;
    $default ||= '';
    if ($initialise) {
        $self->{'_text_variable_refs'}->{$named} = $default;
    }
    return \$self->{'_text_variable_refs'}->{$named} || \$default;
}

sub action {
    my ($self, $named, $callback) = @_;
    unless ($named) {
        warn "usage: $self->action('registeredName', [(CODE_REF)])\n";
        return
          sub { warn "usage: $self->action('registeredName', [(CODE_REF)])\n" };
    }
    if (ref($callback) && ref($callback) eq 'CODE') {
        $self->{'_actions'}->{$named} = $callback;
    }
    return $self->{'_actions'}->{$named}
      || sub { warn "No callback registered for action '$named'\n"; };
}

sub delete_action {
    my ($self, $named) = @_;
    $self->{'_actions'}->{$named} = undef;
    return 1;
}

sub delete_all_actions {
    my ($self) = @_;
    foreach my $name (keys(%{ $self->{'_actions'} })) {
        $self->delete_action($name);
    }
    return;
}

sub DESTROY {
    my ($self) = @_;
    my $t    = $self->title();
    my ($type) = ref($self) =~ /([^:]+)$/;
    warn "Destroying $type named '$t'";
    return;
}

1;

__END__

=head1 NAME - TransientWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


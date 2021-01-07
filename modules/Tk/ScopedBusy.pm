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

package Tk::ScopedBusy;
use strict;
use warnings;
use Carp 'cluck';


=head1 NAME

Tk::ScopedBusy - Busy out a widget until object is dropped

=head1 SYNOPSIS

 my $widget = $self->toplevel;
 my $busy = Tk::ScopedBusy->new($widget, -recurse => 1);
 ...
 return; # $busy is forgotten, and the Unbusy happens

=head1 DESCRIPTION

In addition to exception-safe Busy handling, this module will report
various unexpected transitions in the (implicit) state machine for
Busy.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut


sub new {
    my ($class, $widget, %busy_opt) = @_;

    my $caller = delete $busy_opt{'--caller'};
    $caller ||= join ':', (caller())[1,2];

    my $self = { widget => $widget,
                 caller => $caller };
    bless $self, $class;

    cluck "[w] double-Busy on $widget from $caller in $self\n"
      if $widget->{'Busy'};

    $widget->Busy(%busy_opt);
    my $B = $widget->{'Busy'};

    if ($B) {
        bless $B, 'Tk::ScopedBusy::BusyFellOff'; # just for DESTROY
        # May already have been blessed, for double-Busy
    } else {
        # Perhaps not $widget->viewable ?
        warn "Busy on $widget from $caller had no effect in $self\n";
        $self->{bad_Busy} = 1;
    }

    return $self;
}

sub new_if_not_busy {
    my ($class, $widget, @busy_arg) = @_;
    my $caller = join ':', (caller())[1,2];

    if ($widget->{'Busy'}) {
        warn "[w] $widget is already Busy, at $caller\n";
        return;
    } else {
        return $class->new($widget, '--caller' => $caller, @busy_arg);
    }
}

our $_during_DESTROY = 0;
sub DESTROY {
    my ($self) = @_;
    local $@; # protect against $@ trashing (by Tk::Widget::AUTOLOAD ?)

    my $widget = $self->{widget} || '(GONE)';
    my $caller = $self->{caller} || '(lost)';
    warn "[w] ineffective Busy in $self is cancelled\n" if $self->{bad_Busy};
    if (!Tk::Exists($widget)) {
        my $was_busy =
          ($widget && $widget->{'Busy'}
           ? ' (but it was still Busy)' : '');
        cluck "[w] $widget from $caller did not exist$was_busy when I came to Unbusy it in $self\n";
    }
    if ($widget) {
        warn "[w] double-Unbusy on $widget from $caller in $self\n"
          unless ($widget->{'Busy'} or $self->{bad_Busy});
        local $_during_DESTROY = 1;

        # call it even when !Tk::Exists, because there may be other
        # actions attached
        $widget->Unbusy;
    }
    return;
};

# Tk::ScopedBusy::BusyFellOff object is constructed indirectly, by
# blessing what $widget->Busy puts in $widget->{Busy}
#
# This DESTROY informs you if something else does the $widget->Unbusy
sub Tk::ScopedBusy::BusyFellOff::DESTROY {
    my ($self) = @_;
    local $@; # protect against $@ trashing

    cluck "Busy fell off not during our DESTROY"
      unless $Tk::ScopedBusy::_during_DESTROY;
    return;
}

1;

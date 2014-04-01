package Tk::ScopedBusy;
use strict;
use warnings;


=head1 NAME

Tk::ScopedBusy - Busy out a widget until object is dropped

=head1 SYNOPSIS

 my $widget = $self->toplevel;
 my $busy = Tk::ScopedBusy->new($widget, -recurse => 1);
 ...
 return; # $busy is forgotten, and the Unbusy happens

=cut


sub new {
    my ($class, $widget, @busy_arg) = @_;
    my $caller = join ':', (caller())[1,2];
    my $self = { widget => $widget,
                 caller => $caller };
    bless $self, $class;

    warn "double-Busy on $widget from $caller" if $widget->{'Busy'};
    $widget->Busy(@busy_arg);

    return $self;
}

sub DESTROY {
    my ($self) = @_;
    my $widget = $self->{widget} || '(GONE)';
    my $caller = $self->{caller} || '(lost)';
    if (Tk::Exists($widget)) {
        warn "double-Unbusy on $widget from $caller" unless $widget->{'Busy'};
        $widget->Unbusy;
    } else {
        my $was_busy =
          ($widget && $widget->{'Busy'}
           ? ', but it was still Busy' : '');
        warn "$widget from $caller did not exist when I came to Unbusy it$was_busy";
    }
    return;
};

1;

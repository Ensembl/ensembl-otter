
### EditWindow

package EditWindow;

use strict;
use warnings;

sub new {
    my( $pkg, $tk ) = @_;
    
    my $self = bless {}, $pkg;
    $self->top($tk);
    return $self;
}

sub top {
    my( $self, $top ) = @_;
    
    if ($top) {
        $self->{'_top'} = $top;
    }
    return $self->{'_top'};
}

sub balloon {
    my( $self ) = @_;
    
    $self->{'_balloon'} ||= $self->top->Balloon(
        -state  => 'balloon',
        );
    return $self->{'_balloon'};
}

sub set_minsize {
    my ($self) = @_;
    
    my $top = $self->top;
    $top->update;
    $top->minsize($top->width, $top->height);
    return;
}

sub get_clipboard_text {
    my ($self) = @_;

    my $top = $self->top;
    return unless Tk::Exists($top);

    my ($text);
    eval {
        $text = $top->SelectionGet(
            -selection => 'PRIMARY',
            -type      => 'STRING',
            );
        };
    if ($@) {
        #warn "Clipboard error: $@";
        return;
    } else {
        return $text;
    }
}

1;

__END__

=head1 NAME - EditWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


package Bio::Otter::ServerQuery;

use strict;
use Getopt::Long;
use CGI;

use base 'CGI';

sub new {
    my $class = shift @_;

    my $self = $class->SUPER::new();

    my %vars = $self->Vars();
    GetOptions(\%vars, map { $_.'=s' } @_);

    $self->{_vars} = \%vars;

    return $self;
}

sub getarg {
    my ($self, $argname) = @_;

    return $self->{_vars}->{$argname}
}

sub getargs {
    my $self = shift @_;

    return [ keys %{$self->{_vars}} ];
}

1;


package Bio::Otter::ServerQuery;

use strict;
use Getopt::Long;
use base 'CGI';


sub setarg {
    my ($self, $argname, $argvalue) = @_;

    $self->param($argname, $argvalue);
}

sub getarg {
    my ($self, $argname) = @_;

    warn "Gettting $argname";

    return $self->param($argname);
}


1;


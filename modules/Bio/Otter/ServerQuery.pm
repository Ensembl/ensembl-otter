package Bio::Otter::ServerQuery;

use strict;
use warnings;
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

__END__

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk



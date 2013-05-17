
package Tk::Utils::Dotter;

use strict;
use warnings;

sub problem_box {
    my ($top, $warnings) = @_;
    $top->messageBox(
        -title   => $Bio::Otter::Lace::Client::PFX.'Dotter Problems',
        -icon    => 'warning',
        -message => $warnings,
        -type    => 'OK',
        );
    return;
}

1;

__END__

=head1 NAME - Tk::Utils::Dotter

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

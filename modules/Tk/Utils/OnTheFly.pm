
package Tk::Utils::OnTheFly;

use strict;
use warnings;

sub problem_box {
    my ($top, $title, $warnings) = @_;
    $top->messageBox(
        -title   => 'otter: Problems With ' . $title,
        -icon    => 'warning',
        -message => $warnings->{missing} . $warnings->{remapped} . $warnings->{unclaimed},
        -type    => 'OK',
        );
    return;
}

sub long_query_confirm {
    my ($top, $details) = @_;
    my $response = $top->messageBox(
        -title   => 'otter: Unusually Long Query Sequence',
        -icon    => 'warning',
        -message => $details->{name} . " is "
                  . $details->{length}
                  . " residues long.\n"
                  . "Are you sure you want to try to align it?",
        -type => 'YesNo',
        );
    return ($response eq 'Yes');
}

1;

__END__

=head1 NAME - Tk::Utils::OnTheFly

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

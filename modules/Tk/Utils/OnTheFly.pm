
package Tk::Utils::OnTheFly;

use strict;
use warnings;

sub problem_box {
    my ($top, $title, $warnings) = @_;
    $top->messageBox(
        -title   => $Bio::Otter::Lace::Client::PFX.'Problems With ' . $title,
        -icon    => 'warning',
        -message => $warnings->{missing} . $warnings->{remapped} . $warnings->{unclaimed},
        -type    => 'OK',
        );
    return;
}

sub long_query_confirm {
    my ($top, $details) = @_;
    my $response = $top->messageBox(
        -title   => $Bio::Otter::Lace::Client::PFX.'Unusually Long Query Sequence',
        -icon    => 'warning',
        -message => $details->{name} . " is "
                  . $details->{length}
                  . " residues long.\n"
                  . "Are you sure you want to try to align it?",
        -type => 'YesNo',
        );
    return ($response eq 'Yes');
}

# Caller must supply display_request_feedback() and logger().
#
sub exonerate_callback {
    my ($caller, $request) = @_;
    if (Tk::Exists($caller->top)) {
        $caller->display_request_feedback($request);
    } else {
        $caller->logger->warn('OTF feedback: window gone.');
    }
    return;
}

1;

__END__

=head1 NAME - Tk::Utils::OnTheFly

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

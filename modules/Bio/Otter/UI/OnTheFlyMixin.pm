=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


package Bio::Otter::UI::OnTheFlyMixin;

use strict;
use warnings;

sub problem_box {
    my ($self, $top, $title, $warnings) = @_;
    $top->messageBox(
        -title   => $Bio::Otter::Lace::Client::PFX.'Problems With ' . $title,
        -icon    => 'warning',
        -message => $warnings->{missing} . $warnings->{remapped} . $warnings->{unclaimed} . $warnings->{accession_type},
        -type    => 'OK',
        );
    return;
}

sub long_query_confirm {
    my ($self, $top, $details) = @_;
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

sub exonerate_callback {
    my ($self, $request) = @_;
    if (Tk::Exists($self->top)) {
        $self->display_request_feedback($request);
    } else {
        $self->logger->warn('OTF feedback: window gone.');
    }
    return;
}

sub report_missed_hits {
    my ($self, $where, $request, $flavour) = @_;

    my $top = $where->top;
    $top->deiconify;
    $top->raise;

    my $name = $request->logic_name;
    my $message = "Exonerate of ${name} queries against ${flavour} sequence: ";

    unless ($request->n_hits) {
        $self->_record_missed_hits($where, $message, 'No matches');
        return;
    }

    if ($request->missed_hits and @{$request->missed_hits}) {
        my $details = 'No hits for: ' . join(',', sort @{$request->missed_hits});
        $self->_record_missed_hits($where, $message, $details);
        return;
    }

    return;
}

sub _record_missed_hits {
    my ($self, $where, $message, $details) = @_;
    $self->logger->info($message, $details);
    $where->exception_message($details, $message);
    return;
}

1;

__END__

=head1 NAME - Bio::Otter::UI::OnTheFlyMixin

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

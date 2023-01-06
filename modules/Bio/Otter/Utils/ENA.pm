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


### Bio::Otter::Utils::ENA

package Bio::Otter::Utils::ENA;

use strict;
use warnings;

use LWP::UserAgent;
use Readonly;
use URI::Escape qw(uri_escape);
use XML::Simple;

Readonly my $ENA_VIEW_URL   => 'http://www.ebi.ac.uk/ena/data/view/';
Readonly my $ENA_XML_SUFFIX => '&display=xml';

sub new {
    my ($class, @args) = @_;
    my $self = bless {}, $class;

    my $ua = LWP::UserAgent->new(
        timeout           => 10,
        env_proxy         => 1,
        protocols_allowed => [ 'http' ],
        );

    $self->_user_agent($ua);

    return $self;
}

sub get_sample_accessions {
    my ($self, @accessions) = @_;

    return {} unless @accessions;

    my $acc_list = join(',', map { uri_escape($_) } @accessions);
    my $uri = $ENA_VIEW_URL . $acc_list . $ENA_XML_SUFFIX;
    my $response = $self->_user_agent->get($uri);
    die "No response to ENA request" unless $response;
    unless ($response->is_success) {
        warn $response->status_line;
        return;
    }

    local $XML::Simple::PREFERRED_PARSER = 'XML::Parser';
    # configure expat for speed, also used in Bio::Vega::XML::Parser

    my $xml = $response->decoded_content;
    my $ref = XMLin($xml);

    my %results;
    my $samples = $ref->{SAMPLE};
    if ($samples) {
        $samples = [ $samples ] unless ref($samples) eq 'ARRAY'; # single result comes as hashref not as arrayref
        foreach my $sample (@$samples) {
            my $sample_acc = $sample->{accession};
            $results{$sample_acc} = $sample;
        }
    }

    return \%results;
}

sub get_sample_accession_types {
    my ($self, @accessions) = @_;

    my %acc_types;
    my $results = $self->get_sample_accessions(@accessions);
    foreach my $acc ( keys %$results ) {
        my $result = $results->{$acc};
        $acc_types{$acc} = {
            name        => $acc,
            evi_type    => 'SRA',
            acc_sv      => $acc,
            source      => 'SRA_Sample',
            taxon_list  => $result->{SAMPLE_NAME}->{TAXON_ID},
            description => $result->{TITLE},
        };
    }

    return \%acc_types;
}

sub _user_agent {
    my ($self, @args) = @_;
    ($self->{_user_agent}) = @args if @args;
    return $self->{_user_agent};
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::ENA

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


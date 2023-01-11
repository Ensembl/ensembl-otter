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

package Bio::Otter::Lace::OnTheFly::Builder::Transcript;

use namespace::autoclean;
use Moose;

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)

extends 'Bio::Otter::Lace::OnTheFly::Builder';

has vega_transcript => ( is => 'ro', isa => 'Bio::Vega::Transcript', required => 1 );

around 'prepare_run' => sub {
    my ($orig, $self, @args) = @_;

    my $request = $self->$orig(@args);
    $request->transcript_id($self->vega_transcript->dbID);

    return $request;
};

augment '_build_default_options'    => sub { return { } };
augment '_build_default_qt_options' => sub {
    return {
        protein => { '--model' => 'protein2dna',  '--refine' => 'region' },
        dna     => { '--model' => 'affine:local', '--refine' => 'region' },
    };
};

sub _build_analysis_prefix { return 'OTF_TS_' }

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF

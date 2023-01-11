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

package Bio::Otter::Lace::OnTheFly::Builder::Genomic;

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Builder';

augment '_build_default_options'    => sub {
    my $default_options = {
        '-M'               => 500,
        '--maxintron'      => 200000,
        '--score'          => 100,
        '--softmaskquery'  => 'yes',
        '--showalignment'  => 'false',
    };
    return $default_options;
};

augment '_build_default_qt_options' => sub {
    my $default_qt_options = {
        dna => {
            '--model'           => 'e2g',
            '--geneseed'        => 300,
            '--dnahspthreshold' => 120,
        },
        protein => {
            '--model' => 'p2g',
        },
    };
    return $default_qt_options;
};

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF

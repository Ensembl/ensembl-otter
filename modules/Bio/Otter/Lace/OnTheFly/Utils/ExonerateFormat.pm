=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Lace::OnTheFly::Utils::ExonerateFormat;

use strict;
use warnings;

use Readonly;

use Bio::Otter::Vulgar;

use base qw( Exporter );
our @EXPORT_OK = qw( ryo_format ryo_order sugar_order );

# These must match
#
Readonly my $RYO_FORMAT => 'RESULT: %S %pi %ql %tl %g %V\n';
Readonly my @RYO_ORDER => (
    '_tag',
    @Bio::Otter::Vulgar::SUGAR_ORDER,
    qw(
        _perc_id
        _query_length
        _target_length
        _gene_orientation
      ),
);

sub ryo_format  { return $RYO_FORMAT; }
sub ryo_order   { return @RYO_ORDER;  }
sub sugar_order { return @Bio::Otter::Vulgar::SUGAR_ORDER; }

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF

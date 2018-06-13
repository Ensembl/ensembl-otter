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


### Bio::Vega::ServerAnalysis

package Bio::Vega::ServerAnalysis;

use strict;
use warnings;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

# Bio::Otter::Server::Support::Web object for access to config file params
sub Web {
    my ($self, $Web) = @_;
    
    if ($Web) {
        $self->{'_Web'} = $Web;
    }
    return $self->{'_Web'};
}


1;

__END__

=head1 NAME - Bio::Vega::ServerAnalysis

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


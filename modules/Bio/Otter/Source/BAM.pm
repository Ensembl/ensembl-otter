=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Source::BAM

package Bio::Otter::Source::BAM;

use strict;
use warnings;

use base 'Bio::Otter::Source::BigFile';

sub script_name { return 'bam_get';    }
sub zmap_style  { return 'short-read'; }

sub is_seq_data { return 1; }

sub parent_column {
    my ($self) = @_;
    return $self->{parent_column};
}

sub parent_featureset {
    my ($self) = @_;
    return $self->{parent_featureset};
}

sub coverage_plus {
    my ($self) = @_;
    return $self->{coverage_plus};
}

sub coverage_minus {
    my ($self) = @_;
    return $self->{coverage_minus};
}

1;

__END__

=head1 NAME - Bio::Otter::Source::BAM

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


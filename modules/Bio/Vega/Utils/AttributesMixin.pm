=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Bio::Vega::Utils::AttributesMixin;

use strict;
use warnings;

=head1 NAME

Bio::Vega::Utils::AttributesMixin

=head1 DESCRIPTION

Provides shared method all_Attributes_string() to
L<Bio::Vega::Gene> and L<Bio::Vega::Transcript>, as a mixin.

=head2 B<all_Attributes_string>

Returns all of the attributes as a single string.

We drop any boolean attrib which is false, to avoid
mis-comparing 'absence of attrib' with 'attrib = 0',
which are logically identical.

=cut

my %is_boolean;
BEGIN {
    %is_boolean = map { $_ => 1 } qw(
        mRNA_start_NF
        mRNA_end_NF
        cds_start_NF
        cds_end_NF
    );
}

sub all_Attributes_string {
    my ($self) = @_;

    return join ('-',
        map {$_->code . '=' . $_->value}
        sort {$a->code cmp $b->code || $a->value cmp $b->value}
        grep {not($is_boolean{$_->code}) or $_->value}
        @{$self->get_all_Attributes});
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

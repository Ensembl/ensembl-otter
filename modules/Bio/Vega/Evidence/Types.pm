=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

package Bio::Vega::Evidence::Types;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(new_evidence_type_valid evidence_type_valid_all evidence_is_sra_sample_accession seq_is_protein);

use Readonly;

# Order is important - used for presentation in CanvasWindow::EvidencePaster
# [ note that this list is duplicated in Hum::Ace::SubSeq :-( ]
#
Readonly our @VALID => qw( Protein ncRNA cDNA EST SRA );
Readonly our @ALL   => ( @VALID, 'Genomic');

sub new {
    my ($this) = @_;
    my $class = ref($this) || $this;
    return bless {}, $class;
}

sub list_valid {
    return @VALID;
}

sub list_all {
    return @ALL;
}

sub valid_for_new_evi {
    my ($self, $type) = @_;
    return $self->_in_list($type, \@VALID);
}

sub valid_all {
    my ($self, $type) = @_;
    return $self->_in_list($type, \@ALL);
}

sub _in_list {
    my ($self, $term, $listref) = @_;
    foreach my $item (@$listref) {
        return 1 if $term eq $item;
    }
    return;
}

# This may not be exactly the right place for this, but it'll do for now
#
sub is_sra_sample_accession {
    my ($self, $acc) = @_;

    # Examples:
    #   ERS000123
    #   SRS000012
    #   DRS000234

    return ($acc =~ /^[ESD]RS\d{6}$/);
}

sub is_protein {
    my ($self, $seq) = @_;
    return ($seq =~ /[^acgtrymkswhbvdnACGTRYMKSWHBVDN]/);
}

# Non-member-function wrappers

{
    my $evi_type;

    sub new_evidence_type_valid {
        my ($type) = @_;
        $evi_type ||= __PACKAGE__->new;
        return $evi_type->valid_for_new_evi($type);
    }

    sub evidence_type_valid_all {
        my ($type) = @_;
        $evi_type ||= __PACKAGE__->new;
        return $evi_type->valid_all($type);
    }

    sub evidence_is_sra_sample_accession {
        my ($acc) = @_;
        $evi_type ||= __PACKAGE__->new;
        return $evi_type->is_sra_sample_accession($acc);
    }

    sub seq_is_protein {
        my ($seq) = @_;
        $evi_type ||= __PACKAGE__->new;
        return $evi_type->is_protein($seq);
    }

}

1;

__END__

=head1 NAME - Bio::Vega::Evidence::Types

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


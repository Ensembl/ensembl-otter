=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

package Test::Otter::Accessions;

use strict;
use warnings;

sub new {
    my ($class, @args) = @_;
    return bless {}, $class;
}

sub _init_accessions {
    my ($self) = @_;

    my @accessions;
    my @keys;

    while (<DATA>) {
        chomp;
        next unless /\S/;       # skip empty
        next if     /^\s*#/;    # skip comments

        # First line is fields spec
        unless (@keys) {
            @keys = split /\s+/, $_;
            next;
        }

        my %entry;
        my @fields = map { $_ eq '-' ? undef : $_ } split /\s+/, $_;
        @entry{@keys} = @fields;

        push @accessions, \%entry;
    }

    return \@accessions;
}

sub accessions {
    my ($self) = @_;
    return $self->{accessions} ||= $self->_init_accessions;
}

sub accession_names {
    my ($self) = @_;
    my @names = map { $_->{query} } @{$self->accessions};
    return @names;
}

1;

__DATA__

# Whitespace-separated values
# Fields:

query           acc_sv          mm_db           evi_type        source          currency        pfetch_sha1

# ensembl_cDNA
NM_033513.2     NM_033513.2     refseq          -               -               current
M87879.1        M87879.1        emblrelease     cDNA            EMBL            current         1c369790e301ac7a3f7b4d097d025f9d12176da9
NM_130760.2     NM_130760.2     refseq          -               -               current
AY732484.1      AY732484.1      emblrelease     cDNA            EMBL            current
GU557064.1      GU557064.1      emblrelease     cDNA            EMBL            current

# vertebrate_mRNA
AK125401.1      AK125401.1      emblrelease     cDNA            EMBL            current
BC104468.1      BC104468.1      emblrelease     cDNA            EMBL            current         37284b6cf6d4e32babbe678cb52e26184e81047a
U43628.1        U43628.1        emblrelease     cDNA            EMBL            current
# removed from ENA
CR592900.1      CR592900.1

# EST_Human
BF515365.1      BF515365.1      emblrelease     EST             EMBL            current
AA928768.1      AA928768.1      emblrelease     EST             EMBL            current
AI990682.1      AI990682.1      emblrelease     EST             EMBL            current
BM704540.1      BM704540.1      emblrelease     EST             EMBL            current
AL577183.3      AL577183.3      emblrelease     EST             EMBL            current
AL577183        AL577183.3      emblrelease     EST             EMBL            current

# SwissProt
Q6ZTW0.2        Q6ZTW0.2        uniprot         Protein         SwissProt       current         d613b255d2ff717b4848f2451400c529d12cd358
Q13477-2.2      Q13477-2.2      uniprot_archive Protein         SwissProt       current
Q14031.3        Q14031.3        uniprot         Protein         SwissProt       current
P51124.2        P51124.2        uniprot         Protein         SwissProt       current
Q8IN94.1        Q8IN94.1        uniprot         Protein         SwissProt       current
P35613.2        P35613.2        uniprot         Protein         SwissProt       current
A6NC57-2.3      A6NC57-2.3      uniprot_archive Protein         SwissProt       archived
Q5JPF3-2        Q5JPF3-2.3      uniprot_archive Protein         SwissProt       current
Q5JPF3-2.3      Q5JPF3-2.3      uniprot_archive Protein         SwissProt       current
Q5JPF3-2.2      Q5JPF3-2.2      uniprot_archive Protein         SwissProt       archived

# TrEMBL
B0PJS9.1        B0PJS9.1        uniprot_archive Protein         TrEMBL          archived
D9WMQ1.1        D9WMQ1.1        uniprot         Protein         TrEMBL          current
D5ZU02.1        D5ZU02.1        uniprot         Protein         TrEMBL          current
A5P378.1        A5P378.1        uniprot_archive Protein         TrEMBL          archived

# refseq
NM_001142769.1  NM_001142769.1  refseq          -               -               current         54a8e190de3507a19b981f9f86880c1440df29ea

# SRA (should be ignored by AccessionInfo)
ERS000123

## strange cases
#
# "pfetch -F" fails, RT#282709; Genoscope cDNA
CR590337.1      -               emblrelease     -               -               -               a7af0f725cd46f4a236187b86683b3a3e9570a1f

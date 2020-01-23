#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# RT367298 for erb

# scripts/loutre/find_pfam_domain_locations.pl --dataset mouse Feld-I_B Uteroglobin

use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::FindPFAMDomainLocations;
use parent 'Bio::Otter::Utils::Script';

use Bio::Otter::Lace::SatelliteDB;
use Hum::Sort qw(ace_sort);

sub ottscript_options {
    return (
        dataset_mode          => 'only_one', # for now
        );
}

sub ottscript_validate_args {
    my ($self, $opt, $args) = @_;
    $self->domains(@$args);
    @$args = ();
    return;
}

sub process_dataset {
    my ($self, $dataset) = @_;

    my $pipe_dba = Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $dataset->otter_dba, 'pipeline_db_head', 'Bio::EnsEMBL::DBSQL::DBAdaptor');

    my @results;
    my $pfam_id_sth  = $pipe_dba->dbc->prepare($self->_pfam_id_sql);
    my $genes_sth    = $pipe_dba->dbc->prepare($self->_genes_sql);
    my $gene_adaptor = $pipe_dba->get_GeneAdaptor;

  DOMAIN: foreach my $domain ( $self->domains ) {

        $pfam_id_sth->execute($domain);
        my ($domain_id) = $pfam_id_sth->fetchrow_array;
        unless ($domain_id) {
            warn "Cannot find PFAM domain '$domain'";
            next DOMAIN;
        }

        $genes_sth->execute($domain_id);
        my $genes = $genes_sth->fetchall_arrayref();

      GENE: foreach my $result ( @$genes ) {
            my ($gene_id) = @$result;
            my $gene = $gene_adaptor->fetch_by_dbID($gene_id);
            my $result = $self->project_gene($gene);
            next GENE unless $result;
            push @results, $result;
        }
    }

    my @fields = qw( chr contig domain start end strand );
    say join(',', @fields);

    foreach my $gene ( sort { ace_sort($a->{chr},      $b->{chr}) ||
                                       $a->{start} <=> $b->{start}   } @results )
    {
        say join(',', @{$gene}{@fields});
    }

    return;
}

sub project_gene {
    my ($self, $gene) = @_;

    my $contig_name = $gene->slice->seq_region_name;
    my $proj = $gene->project('chromosome', 'Otter');
    unless (@$proj) {
        my $sr_start = $gene->seq_region_start;
        my $sr_end   = $gene->seq_region_end;
        warn "Cannot project gene ", $gene->dbID, " from $contig_name ($sr_start-$sr_end) to chromosome\n";
        return;
    }
    if (@$proj > 1) {
        warn "Gene ", $gene->dbID, " projects to multiple chromomsome segments\n";
    }
    my $chr_slice = $proj->[0]->to_Slice;
    my $chr = $chr_slice->seq_region_name;
    my $ctg = $gene->slice->seq_region_name;

    return {
        chr    => $chr,
        contig => $ctg,
        start  => $chr_slice->start,
        end    => $chr_slice->end,
        strand => $chr_slice->strand,
        domain => $gene->display_xref->display_id,
      };
}

sub _pfam_id_sql { return q{ SELECT xref_id FROM xref WHERE display_label = ? }; }

sub _genes_sql   { return q{ SELECT gene_id FROM gene WHERE display_xref_id = ? }; }

sub domains {
    my ($self, @args) = @_;
    ($self->{'domains'}) = \@args if @args;
    my $domains = $self->{'domains'} || [];
    return @$domains;
}

# End of module

package main;

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::FindPFAMDomainLocations->import->run;

exit;

# EOF

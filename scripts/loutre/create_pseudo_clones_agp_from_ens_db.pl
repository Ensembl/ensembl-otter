#!/usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
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


### create_pseudo_clones_agp_from_ens_db.pl

use strict;
use warnings;
use Getopt::Long qw{ GetOptions };
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Hum::FastaFileIO;
use Hum::AGP;

{
    my ($chr_name);

    my $usage = sub { exec('perlodc', $0) };
    GetOptions(
        'h|help!'       => \$usage,
        'chromosome=s'  => \$chr_name,
        ) or $usage->();
    $usage->() unless $chr_name;

    my $dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        -user   => 'ensro',
        -group  => 'ensembl',
        # -dbname => 'db8_rattus_norvegicus_core_70_5',
        # -host   => 'genebuild1',
        -dbname => 'avullo_rattus_norvegicus_79_5',
        -host   => 'ens-production',
        );
    my $assembly = $dba->get_CoordSystemAdaptor->fetch_by_name('chromosome')->version;
    my $chr_length = $dba->get_SliceAdaptor->fetch_by_region('chromosome', $chr_name)->length;
    my $pc_length = 100_000;
    printf STDERR "Fetched chr %s (length = %d)\n", $chr_name, $chr_length;
    my $agp = Hum::AGP->new;
    $agp->chr_name($chr_name);
    my $prev_agp_row;
    for (my $i = 1, my $start = 1; $start < $chr_length; $i++, $start += $pc_length) {
        my $end = $start + $pc_length - 1;
        $end = $chr_length if $end > $chr_length;
        my $agp_row_length = $end - $start + 1;
        my $ctg = $dba->get_SliceAdaptor->fetch_by_region('chromosome', $chr_name, $start, $end);
        # my $ctg_name = sprintf "Rn50_%s_%04d.1", $chr_name, $i;
        my $ctg_name = sprintf "Rn60_%s_%04d.1", $chr_name, $i;
        my $dna = $ctg->seq;

        # If this region is entirely "n", add it as a gap.
        if ($dna =~ /^[nN]*$/) {
            if ($prev_agp_row and $prev_agp_row->is_gap) {
                $prev_agp_row->chr_length($prev_agp_row->chr_length + $agp_row_length);
            }
            else {
                my $gap = $prev_agp_row = $agp->new_Gap;
                $gap->chr_length($agp_row_length);
            }
            next;
        }

        warn "$ctg_name ($start)\n";

        my $row = $prev_agp_row = $agp->new_Clone;
        $row->accession_sv($ctg_name);
        $row->phase_letter('W');
        $row->seq_start(1);
        $row->seq_end($agp_row_length);
        $row->strand(1);

        my $seq = Hum::Sequence::DNA->new;
        $seq->name($ctg_name);
        $seq->sequence_string($dna);
        Hum::FastaFileIO->new_DNA_IO("> $ctg_name.seq")->write_sequences($seq);
    }

    my $agp_file = sprintf '%s_chr_%s.agp', $assembly, $chr_name;
    open my $AGP, '>', $agp_file or die "Can't write to '$agp_file'; $!";
    print $AGP $agp->string;
    close $AGP or die "Error writing to '$agp_file'; $!";
}


__END__

=head1 NAME - create_pseudo_clones_agp_from_ens_db.pl

=head1 DESCRIPTION

Connect to an Ensembl database and fetch a chromosome, writing out an AGP
and sequence files for use by

  ensembl-pipeline/scripts/Finished/load_loutre_pipeline.pl

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


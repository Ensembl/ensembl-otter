#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
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


### dump_chromosomes.pl

use strict;
use warnings;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::Server::Config;
use Hum::FastaFileIO;
use Hum::Sort qw{ ace_sort };

{
    my( $dataset_name, $equiv_asm );

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
        'equiv_asm=s'   => \$equiv_asm,
        ) or $usage->();
    $usage->() unless $dataset_name and $equiv_asm;

    # DataSet interacts directly with an otter database
    my $ds = Bio::Otter::Server::Config->SpeciesDat->dataset($dataset_name);

    my $otter_dba = $ds->otter_dba;
    
    my $out = Hum::FastaFileIO->new(\*STDOUT);
    
    my $slice_list = $otter_dba->get_SliceAdaptor->fetch_all('toplevel');
    @$slice_list = sort { ace_sort($a->seq_region_name, $b->seq_region_name) } @$slice_list;
    while (my $slice = shift @$slice_list) {
        my ($asm_version) = @{$slice->get_all_Attributes('equiv_asm')};
        if ($asm_version) {
            next unless $asm_version->value eq $equiv_asm;
        }
        else {
            next;
        }
        print STDERR $slice->seq_region_name, "\t", $asm_version->value, "\n";
        my $seq = Hum::Sequence->new;
        $seq->name($slice->seq_region_name);
        $seq->sequence_string($slice->seq);
        $out->write_sequences($seq);
    }
}




__END__

=head1 NAME - dump_chromosomes.pl

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


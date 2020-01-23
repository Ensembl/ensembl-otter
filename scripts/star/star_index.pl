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


### star_index.pl

use strict;
use warnings;
use Getopt::Long qw{ GetOptions };
use File::Temp qw{ tmpnam };

{
    my $usage = sub{ exec('perldoc', $0) };
    my $genome_fasta = '';
    my $run_flag = 0;
    GetOptions(
        'h|help!'   => $usage,
        'fasta=s'   => \$genome_fasta,
        'run!'      => \$run_flag,
    ) or $usage->();
    $usage->() unless $genome_fasta;

    my $genome = $genome_fasta;
    $genome =~ s/\.[^\.]+$//;
    $genome .= ".star";

    my $max_mem   = 27_000_000_000; # Need approx 10x genome size with default parameters.
    my $lsf_mem   = ($max_mem / 1e6) + 8_000;
    my $n_threads = 4;

    if ($run_flag) {
        mkdir($genome) or die "Could not mkdir($genome); $!";
        my @cmd = (
            'STAR',
            '--runMode'                => 'genomeGenerate',
            '--genomeDir'              => $genome,
            '--genomeFastaFiles'       => $genome_fasta,
            '--runThreadN'             => $n_threads,
            '--limitGenomeGenerateRAM' => $max_mem,
            '--outTmpDir'              => scalar(tmpnam()),

            # '--genomeSAsparseD'     => 2,
            # '--genomeSAindexNbases' => 15,
            # '--genomeChrBinNbits'   => 15,
        );
        system(@cmd);
    }
    else {
        my $star_v = "STAR_2.4.2a";
        $ENV{'PATH'} = "/software/svi/bin/$star_v/bin/Linux_x86_64:$ENV{PATH}";
        my @bsub = (
            'bsub',
            -q => 'normal',
            -n => $n_threads,
            -M => $lsf_mem,
            -R => "select[mem>$lsf_mem] rusage[mem=$lsf_mem] span[hosts=1]",
            -o => "$genome.out",
            -e => "$genome.err",
            $0, '-run',
            -fasta => $genome_fasta,
        );
        # print STDERR "@bsub\n";
        system(@bsub);
    }
}

__END__

=head1 NAME - star_index.pl

=head1 SYNOPSIS

  star_index.pl -fasta <GENOME.fasta>

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


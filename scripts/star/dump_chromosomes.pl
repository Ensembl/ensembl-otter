#!/usr/bin/env perl

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


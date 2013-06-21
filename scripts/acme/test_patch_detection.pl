#!/usr/bin/env perl

package Bio::Otter::Script::TestPatchDetection;

use strict;
use warnings;
use 5.010;

use Bio::Vega::PatchMapper;

use parent 'Bio::Otter::Utils::Script';

sub ottscript_validate_args {
    my ($self, $opt, $args) = @_;
    $self->usage_error("No args allowed") if @$args;
    return;
}

sub ottscript_options {
    return (
        dataset_mode => 'only_one',
        sequence_set => 'required',
        );
}

sub process_dataset {
    my ($self, $dataset, $sequence_set) = @_;
    say "processing ", $sequence_set->name;

    # my $patch_mapper = Bio::Vega::PatchMapper->new($sequence_set);
    my $sub_set = $sequence_set->sub_Slice(21000000, 21500000);
    my $patch_mapper = Bio::Vega::PatchMapper->new($sub_set);

    my $equiv_slice = $patch_mapper->_equiv_slice;
    my $equiv_name = $equiv_slice->seq_region_name;
    my $equiv_asm  = $equiv_slice->coord_system->version;

    my @results = $patch_mapper->patches;
    foreach my $p (@results) {
        say sprintf('(%6d) %-30s: %9d - %9d [%4d]', $p->seq_region_id, $p->name, $p->start, $p->end, $p->n_cmps);
        say "\tGot ", $p->n_map_segs, " segments mapping to '$equiv_name' ($equiv_asm)";
        my ($p_min, $p_max) = ($p->chr_start, $p->chr_end);
        say "\t$p_min - $p_max";

        my $fpc = $p->feature_per_contig;
        say "\tFeatures: ", scalar(keys %$fpc);

        foreach my $ctg (keys %$fpc) {
            my $sf = $fpc->{$ctg};
            if ($sf->seq_region_start < $p->chr_start or $sf->seq_region_end > $p->chr_end) {
                say "\t\tOops: ", $ctg;
            }
        }
    }
    my $all_features = $patch_mapper->all_features;
    say "All features: ", scalar @$all_features;
    return;
}

# End of module

package main;

Bio::Otter::Script::TestPatchDetection->import->run;

exit;

# EOF

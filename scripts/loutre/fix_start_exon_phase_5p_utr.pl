#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::FixStartExonPhase5P_UTR;
use parent 'Bio::Otter::Utils::Script';

use Bio::Otter::ServerAction::Region;

sub ottscript_options {
    return (
        dataset_mode          => 'only_one', # for now
        dataset_class         => 'Bio::Otter::DataSet::FixStartExonPhase5P_UTR',
        gene_class            => 'Bio::Otter::Gene::FixStartExonPhase5P_UTR',
        allow_iteration_limit => 1,
        allow_modify_limit    => 1,
        );
}

sub process_dataset {
  my ($self, $dataset) = @_;

  $dataset->iterate_genes(\&do_gene);

  return;
}

sub do_gene {
    my ($dataset, $script_gene) = @_;

    my %ts_map = map { $_ => 1 } split ',', $script_gene->transcripts;

    my $local_server = $dataset->local_server;
    $local_server->set_params(
        dataset => $dataset->name,
        type    => $script_gene->seq_region_name,
        start   => $script_gene->start,
        end     => $script_gene->end,
        cs      => $script_gene->cs_name,
        csver   => $script_gene->cs_version,
        );
    my $sa_region = Bio::Otter::ServerAction::Region->new_with_slice($local_server);
    my $region = $sa_region->get_region;

    my $verbose = $dataset->verbose;
    my ($msg, $verbose_msg);

    my $gene;
    foreach my $g ($region->genes) {
        if ($g->dbID == $script_gene->gene_id) {
            $gene = $g;
        } else {
            $verbose_msg .= "\n\tSkipping " . $g->stable_id;
        }
    }

    foreach my $ts ( @{$gene->get_all_Transcripts} ) {
        next unless $ts_map{$ts->dbID};
        my $ts_msg = sprintf("\n\t%s", $ts->stable_id);
        $msg .= $ts_msg;
        $verbose_msg .= $ts_msg;
    }

    return ($msg, $verbose_msg);
}

# End of module

package Bio::Otter::DataSet::FixStartExonPhase5P_UTR;
use Moose;
extends 'Bio::Otter::Utils::Script::DataSet';

around 'gene_sql' => sub {
    my ($orig, $self) = @_;
    my $sql = $self->$orig();
    $sql =~ s/__EXTRA_COLUMNS__/
              , cs.name    AS cs_name
              , cs.version AS cs_version
              , GROUP_CONCAT(DISTINCT ts.transcript_id) AS transcripts /;
    $sql =~ s/__EXTRA_JOINS__/
              JOIN transcript   ts ON ts.gene_id        = g.gene_id
              JOIN translation  tl ON tl.translation_id = ts.canonical_translation_id
              JOIN exon         se ON se.exon_id        = tl.start_exon_id
              JOIN coord_system cs ON cs.coord_system_id = sr.coord_system_id /;
    $sql =~ s/__EXTRA_CONDITIONS__/
              AND srh.value != 1    -- not hidden
              AND ts.is_current = 1
              AND tl.seq_start > 1
              AND se.phase != -1 /;
    $sql =~ s/__GROUP_BY__/
              GROUP BY g.gene_id /;
    return $sql;
};

# End of module

package Bio::Otter::Gene::FixStartExonPhase5P_UTR;
use Moose;
extends 'Bio::Otter::Utils::Script::Gene';

has 'cs_name'     => ( is => 'ro', isa => 'Str', required => 1 );
has 'cs_version'  => ( is => 'ro', isa => 'Str', required => 1 );
has 'transcripts' => ( is => 'ro', isa => 'Str', required => 1 );

# End of module

package main;

Bio::Otter::Script::FixStartExonPhase5P_UTR->import->run;

exit;

# EOF

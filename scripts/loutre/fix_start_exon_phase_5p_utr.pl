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


use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::FixStartExonPhase5P_UTR;
use parent 'Bio::Otter::Utils::Script';

use Sys::Hostname;
use Try::Tiny;

use Bio::Otter::ServerAction::Script::Region;

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

  $dataset->iterate_genes( sub { my ($dataset, $gene) = @_; return $self->do_gene($dataset, $gene); } );

  return;
}

sub do_gene {
    my ($self, $dataset, $script_gene) = @_;

    my %ts_map = map { $_ => 1 } split ',', $script_gene->transcripts;

    # Possibly some of this region/slice stuff should go into a DataSet method
    my $local_server = $dataset->local_server;
    $local_server->set_params(
        dataset => $dataset->name,
        type    => $script_gene->seq_region_name,
        start   => $script_gene->start,
        end     => $script_gene->end,
        cs      => $script_gene->cs_name,
        csver   => $script_gene->cs_version,
        );
    my $region_action = Bio::Otter::ServerAction::Script::Region->new_with_slice($local_server);
    my $region = $region_action->get_region;

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

    my $changed;
    foreach my $ts ( @{$gene->get_all_Transcripts} ) {
        next unless $ts_map{$ts->dbID};

        my $tl = $ts->translation;
        my $se = $tl->start_Exon;

        my $status = '';
        if ($tl->start > 0 and $se->phase != -1) {
            $status = $se->stable_id . ' needs fixing';
            $se->phase(-1);
            $changed = 1;
        } else {
            $status = 'SELECTED IN ERROR!';
        }
        my $ts_msg = sprintf("\n\t%s [%s]", $ts->stable_id, $status);
        $msg .= $ts_msg;
        $verbose_msg .= $ts_msg;
    }

    my $g_msg = "gene not modified";
    if ($changed) {
        if ($dataset->may_modify) {
            $local_server->authorized_user($gene->gene_author->name); # preserve authorship
            $g_msg = $self->_write_gene_region($region_action, $region);
            $dataset->inc_modified_count;
        } else {
            $g_msg = "gene modified: would write region here"
        }
    }

    $g_msg = "\n\t" . $g_msg;
    $msg .= $g_msg;
    $verbose_msg .= $g_msg;

    return ($msg, $verbose_msg);
}

sub _write_gene_region {
    my ($self, $region_action, $region) = @_;

    my @msg;

    my $lock;
    try {
        $region_action->server->add_param( hostname => hostname );
        $lock = $region_action->lock_region;
        push @msg, 'lock ok';
    }
    catch {
        my ($err) = ($_ =~ m/^MSG: (Failed to lock.*)$/m);
        push @msg, "lock failed: '$err'";
    };

    if ($lock) {
        my $new_region;
        try {
            $region_action->server->set_params( data => $region );
            $new_region = $region_action->write_region;
            push @msg, 'write ok';
        }
        catch {
            my $err = $_;
            chomp $err;
            push @msg, "write failed: '$err'";
        };

        $region_action->server->set_params( data => $lock );
        $region_action->unlock_region;
        push @msg, 'unlock ok';
    }

    return join(',', @msg);
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

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::FixStartExonPhase5P_UTR->import->run;

exit;

# EOF

#!/usr/bin/env perl
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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


# FIXME: copied from, and lots of duplication with, fix_start_exon_phase_5p.pl

use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::FixEndExonEndPhase;
use parent 'Bio::Otter::Utils::Script';

use Sys::Hostname;
use Try::Tiny;

use Bio::Otter::ServerAction::Script::Region;

sub ottscript_options {
    return (
        dataset_mode          => 'only_one', # for now
        dataset_class         => 'Bio::Otter::DataSet::FixEndExonEndPhase',
        gene_class            => 'Bio::Otter::Gene::FixEndExonEndPhase',
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
        chr     => $script_gene->seq_region_name,
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
    return ($msg, $verbose_msg) unless $gene;

    my %exon_map;

    my $changed;
    foreach my $ts ( @{$gene->get_all_Transcripts} ) {
        next unless $ts_map{$ts->dbID};

        my $tl      = $ts->translation;
        my $ee      = $tl->end_Exon;
        my $strand  = $ee->strand;
        my $tl_low  = $ts->coding_region_start;
        my $tl_high = $ts->coding_region_end;

        my $status = '';
        if ($ee->end_phase == -1 and (
                   ($strand ==  1 and $tl_high == $ee->end)
                or ($strand == -1 and $tl_low  == $ee->start))) {

            my $actual_end_phase;
            if ($ee->dbID == $tl->start_Exon->dbID) {
                # Coding region is in one exon
                my $coding_length;
                if ($strand == 1) {
                    $coding_length = $ee->end - $tl_low + 1;
                } else {
                    $coding_length = $tl_high - $ee->start + 1;
                }
                $actual_end_phase = $coding_length % 3;
            } else {
                # Multi-exon coding region
                $actual_end_phase = ($ee->length + $ee->phase) % 3;
            }

            $status = sprintf("%s: correcting bad end_phase, was -1, now %d",
                              $ee->stable_id, $actual_end_phase);

            $ee->end_phase($actual_end_phase);
            $ee->stable_id(undef);
            $changed = 1;

            if (my $id = $exon_map{$ee+0}) {
                warn sprintf("Already seen this exon object as dbID %d, now as dbID %d (%s)\n",
                             $id, $ee->dbID, $ee->stable_id);
            } else {
                $exon_map{$ee+0} = $ee->dbID;
            }

        } else {
            next;               # we only selected on end_phase and existence of translation
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
            $region_action->server->set_params( data => $region, locknums => $lock->{locknums} );
            $new_region = $region_action->write_region;
            push @msg, 'write ok';
        }
        catch {
            my $err = $_;
            chomp $err;
            push @msg, "write failed: '$err'";
        };

        $region_action->server->set_params( locknums => $lock->{locknums} );
        $region_action->unlock_region;
        push @msg, 'unlock ok';
    }

    return join(',', @msg);
}

# End of module

package Bio::Otter::DataSet::FixEndExonEndPhase;
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
              JOIN exon         ee ON ee.exon_id        = tl.end_exon_id
              JOIN coord_system cs ON cs.coord_system_id = sr.coord_system_id /;
    $sql =~ s/__EXTRA_CONDITIONS__/
              AND ts.is_current = 1
              AND ee.end_phase = -1
              AND srh.value = 0 /;
    $sql =~ s/__GROUP_BY__/
              GROUP BY g.gene_id /;
    return $sql;
};

# End of module

package Bio::Otter::Gene::FixEndExonEndPhase;
use Moose;
extends 'Bio::Otter::Utils::Script::Gene';

has 'cs_name'     => ( is => 'ro', isa => 'Str', required => 1 );
has 'cs_version'  => ( is => 'ro', isa => 'Str', required => 1 );
has 'transcripts' => ( is => 'ro', isa => 'Str', required => 1 );

# End of module

package main;

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::FixEndExonEndPhase->import->run;

exit;

# EOF

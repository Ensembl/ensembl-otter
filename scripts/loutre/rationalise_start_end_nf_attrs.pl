package Bio::Otter::Script::RationaliseStartEndNFAttrs;

use strict;
use warnings;
use 5.010;

use parent 'Bio::Otter::Utils::Script';

sub ottscript_options {
    return (
        dataset_mode => 'only_one', # for now
        );
}

sub process_dataset {
  my ($self, $dataset) = @_;
  my $ds_name = $dataset->name;
  $dataset->iterate_transcripts(\&do_transcript);
  return;
}

sub do_transcript {
    my ($self, $ts) = @_;

    my $ts_name   = $ts->name;
    my $sr_name   = $ts->seq_region_name;
    my $sr_hidden = $ts->seq_region_hidden;

    my $sth = $self->find_attrs_sth($ts);
    $sth->execute($ts->transcript_id);
    my $rows = $sth->fetchall_arrayref({});

    if (@$rows) {
        my $attrs = join(',', map { $_->{code} . '=' . $_->{value} } @$rows);
        say "\tTranscript '$ts_name' on '$sr_name' ($sr_hidden): ", scalar(@$rows), ": ", $attrs;
    }
    return;
}

{
    my $_find_attr_sth;

    sub find_attrs_sth {
        my ($self, $ts) = @_;
        unless ($_find_attr_sth) {
            # It's a bit clumsy that we need to go via the transcript for this
            my $dbc = $ts->dataset->otter_dba->dbc;
            $_find_attr_sth = $dbc->prepare(q{
                SELECT
                  ta.transcript_id  as transcript_id,
                  ta.attrib_type_id as attrib_type_id,
                  at.code           as code,
                  ta.value          as value
                FROM
                       transcript        t
                  JOIN transcript_attrib ta ON t.transcript_id = ta.transcript_id
                  JOIN attrib_type       at ON ta.attrib_type_id = at.attrib_type_id
                WHERE
                      t.transcript_id = ?
                  AND ta.value        = 0
                  AND at.code IN (
                    'mRNA_start_NF',
                    'mRNA_end_NF',
                    'cds_start_NF',
                    'cds_end_NF'
                  )
            });
        }
        return $_find_attr_sth;
    }

}

# End of module

package main;

Bio::Otter::Script::RationaliseStartEndNFAttrs->import->run;

exit;

# EOF

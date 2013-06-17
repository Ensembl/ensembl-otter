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

  my $sth = $self->find_attrs_sth($dataset);
  $dataset->callback_data('find_attrs_sth' => $sth);

  $dataset->iterate_transcripts(\&do_transcript);

  return;
}

sub do_transcript {
    my ($dataset, $ts) = @_;

    my $sth = $dataset->callback_data('find_attrs_sth');
    $sth->execute($ts->transcript_id);
    my $rows = $sth->fetchall_arrayref({});

    my $msg;
    my $verbose_msg = 'ok';

    if (@$rows) {
        my $n = scalar(@$rows);
        $msg = "$n to delete";
        if ($dataset->verbose) {
            my $attrs    = join(',', map { $_->{code} . '=' . $_->{value} } @$rows);
            $verbose_msg = "$n - $attrs";
        }
    }
    return ($msg, $verbose_msg);
}

sub find_attrs_sth {
    my ($self, $dataset) = @_;

    my $dbc = $dataset->otter_dba->dbc;
    my $sth = $dbc->prepare(q{
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
    return $sth;
}

# End of module

package main;

Bio::Otter::Script::RationaliseStartEndNFAttrs->import->run;

exit;

# EOF

package Bio::Otter::Utils::Script::DataSet;

use 5.010;
use namespace::autoclean;

use Bio::Otter::Utils::Script::Transcript;

use Moose;

has 'otter_sd_ds' => (
    is       => 'ro',
    isa      => 'Bio::Otter::SpeciesDat::DataSet',
    handles  => [ qw( name params otter_dba pipeline_dba satellite_dba ) ],
    required => 1,
    );

has 'script' => (
    is       => 'ro',
    isa      => 'Bio::Otter::Utils::Script',
    weak_ref => 1,
    handles  => [ qw( setup_data verbose ) ],
    );

has '_transcript_sth' => (
    is      => 'ro',
    builder => '_build_transcript_sth',
    lazy    => 1,
    );

sub iterate_transcripts {
    my ($self, $ts_method) = @_;

    my $sth = $self->_transcript_sth;
    $sth->execute;

    while (my $cols = $sth->fetchrow_hashref) {
        my $ts = Bio::Otter::Utils::Script::Transcript->new(%$cols, dataset => $self);
        if ($self->verbose) {
            my $stable_id = $ts->stable_id;
            my $name      = $ts->name;
            say "  $stable_id ($name)";
        }
        $self->script->$ts_method($ts);
    }
    return;
}

sub _build_transcript_sth {
    my $self = shift;
    my $dbc = $self->otter_dba->dbc;
    my $sth = $dbc->prepare(q{
        SELECT
                g.gene_id        as gene_id,
                g.stable_id      as gene_stable_id,
                gan.value        as gene_name,
                t.transcript_id  as transcript_id,
                t.stable_id      as transcript_stable_id,
                tan.value        as transcript_name,
                sr.name          as seq_region_name,
                srh.value        as seq_region_hidden
        FROM
                transcript           t
           JOIN gene                 g   ON t.gene_id = g.gene_id
           JOIN gene_attrib          gan ON g.gene_id = gan.gene_id
                                        AND gan.attrib_type_id = (
                                              SELECT attrib_type_id
                                              FROM   attrib_type
                                              WHERE  code = 'name'
                                            )
           JOIN transcript_attrib    tan ON t.transcript_id = tan.transcript_id
                                        AND tan.attrib_type_id = (
                                              SELECT attrib_type_id
                                              FROM   attrib_type
                                              WHERE  code = 'name'
                                            )
           JOIN seq_region           sr  ON g.seq_region_id = sr.seq_region_id
           JOIN seq_region_attrib    srh ON sr.seq_region_id = srh.seq_region_id
                                        AND srh.attrib_type_id = (
                                              SELECT attrib_type_id
                                              FROM   attrib_type
                                              WHERE  code = 'hidden'
                                            )
        WHERE
                t.is_current = 1
            AND g.is_current = 1
        ORDER BY g.stable_id, t.stable_id
    });
    return $sth;
}

__PACKAGE__->meta->make_immutable;

1;

# EOF

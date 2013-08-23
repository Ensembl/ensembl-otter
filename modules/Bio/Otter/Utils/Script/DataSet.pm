package Bio::Otter::Utils::Script::DataSet;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use 5.010;
use namespace::autoclean;

use Bio::Otter::Utils::Script::Gene;
use Bio::Otter::Utils::Script::Transcript;

use Bio::Otter::LocalServer;

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
    handles  => [ qw( setup_data dry_run may_modify inc_modified_count verbose ) ],
    );

has 'local_server' => (
    is       => 'ro',
    isa      => 'Bio::Otter::LocalServer',
    builder  => '_build_local_server',
    lazy     => 1,
    );

has '_callback_data' => (
    traits   => ['Hash'],
    is       => 'ro',
    isa      => 'HashRef',        # not up to us to police the contents
    default  => sub { {} },
    init_arg => undef,
    handles  => {
        callback_data => 'accessor',
    },
    );

has '_transcript_sth' => (
    is      => 'ro',
    builder => '_build_transcript_sth',
    lazy    => 1,
    );

has '_gene_sth' => (
    is      => 'ro',
    builder => '_build_gene_sth',
    lazy    => 1,
    );

sub _build_local_server {
    my $self = shift;
    return Bio::Otter::LocalServer->new( otter_dba => $self->otter_dba );
}

sub _iterate_something {
    my ($self, $obj_method, $sth, $obj_class) = @_;

    $sth->execute;

    my $count = 0;
    while (my $cols = $sth->fetchrow_hashref) {
        my $obj = $obj_class->new(%$cols, dataset => $self);
        my ($msg, $verbose_msg) = $self->$obj_method($obj);
        ++$count;
        my $stable_id = $obj->stable_id;
        if ($self->verbose) {
            $verbose_msg ||= '.';
            my $name      = $obj->name;
            my $sr_name   = $obj->seq_region_name;
            my $sr_hidden = $obj->seq_region_hidden ? " (HIDDEN)" : "";
            say "  $stable_id ($name) [${sr_name}${sr_hidden}]: $verbose_msg";
        } elsif ($msg) {
            say "$stable_id: $msg";
        }
    }
    say "Modified ", $self->script->modified_count, " of $count transcripts" if $self->verbose;
    return;
}

sub iterate_transcripts {
    my ($self, $ts_method) = @_;
    return $self->_iterate_something($ts_method, $self->_transcript_sth, $self->script->_option('transcript_class'));
}

sub transcript_sql {
    my $self = shift;
    my $sql = q{
        SELECT
                g.gene_id          AS gene_id,
                g.stable_id        AS gene_stable_id,
                gan.value          AS gene_name,
                t.transcript_id    AS transcript_id,
                t.stable_id        AS transcript_stable_id,
                t.seq_region_start AS transcript_start,
                t.seq_region_end   AS transcript_end,
                tan.value          AS transcript_name,
                sr.name            AS seq_region_name,
                srh.value          AS seq_region_hidden
                __EXTRA_COLUMNS__
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
           __EXTRA_JOINS__
        WHERE
                t.is_current = 1
            AND g.is_current = 1
            __EXTRA_CONDITIONS__
        __GROUP_BY__
        ORDER BY g.stable_id, t.stable_id
        __LIMIT__
    };
    return $sql;
}

sub _build_transcript_sth {
    my $self = shift;
    return $self->_build_sth($self->transcript_sql);
}

sub iterate_genes {
    my ($self, $ts_method) = @_;
    return $self->_iterate_something($ts_method, $self->_gene_sth, $self->script->_option('gene_class'));
}

sub gene_sql {
    my $self = shift;
    my $sql = q{
        SELECT
                g.gene_id          AS gene_id,
                g.stable_id        AS gene_stable_id,
                g.seq_region_start AS gene_start,
                g.seq_region_end   AS gene_end,
                gan.value          AS gene_name,
                sr.name            AS seq_region_name,
                srh.value          AS seq_region_hidden
                __EXTRA_COLUMNS__
        FROM
                gene                 g
           JOIN gene_attrib          gan ON g.gene_id = gan.gene_id
                                        AND gan.attrib_type_id = (
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
           __EXTRA_JOINS__
        WHERE
                g.is_current = 1
                __EXTRA_CONDITIONS__
        __GROUP_BY__
        ORDER BY g.stable_id
        __LIMIT__
    };
    return $sql;
}

sub _build_gene_sth {
    my $self = shift;
    return $self->_build_sth($self->gene_sql);
}

sub _build_sth {
    my ($self, $sql) = @_;
    my $dbc = $self->otter_dba->dbc;

    # I'd really rather use DBIx::Class...

    my $limit = $self->script->limit ? $self->script->limit : '';
    $sql =~ s/__LIMIT__/LIMIT $limit/;

    foreach my $key (qw( COLUMNS JOINS CONDITIONS )) {
        my $placeholder = "__EXTRA_${key}__";
        $sql =~ s/$placeholder//;
    }
    $sql =~ s/__GROUP_BY__//;

    my $sth = $dbc->prepare($sql);
    return $sth;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF

=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Otter::Utils::Script::DataSet;

use 5.010;
use namespace::autoclean;

use Carp;
use Sys::Hostname;
use Try::Tiny;

use Bio::Otter::Utils::Script::Gene;
use Bio::Otter::Utils::Script::Transcript;

use Bio::Otter::Server::Support::Local;
use Bio::Otter::ServerAction::Script::Region;

use Moose;

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)

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
    handles  => [ qw( setup_data dry_run may_modify inc_modified_count modified_count verbose ) ],
    );

has 'local_server' => (
    is       => 'ro',
    isa      => 'Bio::Otter::Server::Support::Local',
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

has 'transcript_adaptor' => (
    is      => 'ro',
    builder => '_build_transcript_adaptor',
    lazy    => 1,
    );

has '_gene_sth' => (
    is      => 'ro',
    builder => '_build_gene_sth',
    lazy    => 1,
    );

has 'gene_adaptor' => (
    is      => 'ro',
    builder => '_build_gene_adaptor',
    lazy    => 1,
    );

sub _build_local_server {
    my $self = shift;
    return Bio::Otter::Server::Support::Local->new( otter_dba => $self->otter_dba );
}

sub _iterate_something {
    my ($self, $obj_method, $sth, $obj_class, $desc) = @_;

    $sth->execute;

    my $count = 0;
    while (my $cols = $sth->fetchrow_hashref) {
        my $obj = $obj_class->new(%$cols, dataset => $self);
        my ($msg, $verbose_msg) = $self->$obj_method($obj);
        ++$count;
        my $stable_id = $obj->stable_id // '<no_stable_id>';
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
    $desc //= 'objects';
    say "Modified ", $self->modified_count, " of $count $desc" if $self->verbose;
    return;
}

sub iterate_transcripts {
    my ($self, $ts_method) = @_;
    ## no critic(Subroutines::ProtectPrivateSubs)
    return $self->_iterate_something($ts_method, $self->_transcript_sth, $self->script->_option('transcript_class'), 'transcripts');
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

sub fetch_vega_transcript_by_stable_id {
    my ($self, $stable_id) = @_;
    return $self->transcript_adaptor->fetch_by_stable_id($stable_id);
}

sub _build_transcript_adaptor {
    my $self = shift;
    return $self->otter_dba->get_TranscriptAdaptor;
}

sub iterate_genes {
    my ($self, $ts_method) = @_;
    ## no critic(Subroutines::ProtectPrivateSubs)
    return $self->_iterate_something($ts_method, $self->_gene_sth, $self->script->_option('gene_class'), 'genes');
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

sub fetch_vega_gene_by_stable_id {
    my ($self, $stable_id) = @_;
    return $self->gene_adaptor->fetch_by_stable_id($stable_id);
}

sub _build_gene_adaptor {
    my $self = shift;
    return $self->otter_dba->get_GeneAdaptor;
}

sub _build_sth {
    my ($self, $sql) = @_;
    my $dbc = $self->otter_dba->dbc;

    # I'd really rather use DBIx::Class...

    my $limit = $self->script->limit ? 'LIMIT ' . $self->script->limit : '';
    $sql =~ s/__LIMIT__/$limit/;

    foreach my $key (qw( COLUMNS JOINS CONDITIONS )) {
        my $placeholder = "__EXTRA_${key}__";
        $sql =~ s/$placeholder//;
    }
    $sql =~ s/__GROUP_BY__//;

    my $sth = $dbc->prepare($sql);
    return $sth;
}

sub fetch_region_by_slice {
    my ($self, %args) = @_;
    my $slice = $args{slice} or croak "fetch_region_by_slice(): must supply slice argument";

    my $start = $args{start} || $slice->start;
    my $end   = $args{end}   || $slice->end;

    my $local_server = $self->local_server;
    $local_server->set_params(
        dataset => $self->name,
        type    => $slice->seq_region_name,
        start   => $start,
        end     => $end,
        cs      => $slice->coord_system->name,
        csver   => $slice->coord_system->version,
        );
    my $region_action = Bio::Otter::ServerAction::Script::Region->new_with_slice($local_server);
    my $region = $region_action->get_region;

    return $region;
}

sub write_region {
    my ($self, $region, $author) = @_;

    my @msg;
    my $new_region;

  WRITE_REGION: {

      my $region_action = $region->server_action;
      unless ($region_action) {
          push @msg, 'no server_action set for region';
          last WRITE_REGION;
      }

      if ($author) {
          $region_action->server->authorized_user($author);
      }

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
      last WRITE_REGION unless $lock;

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

    } # WRITE_REGION

    return ($new_region, join(',', @msg));
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF

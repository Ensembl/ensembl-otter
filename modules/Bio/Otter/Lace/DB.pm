
### Bio::Otter::Lace::DB

package Bio::Otter::Lace::DB;

use strict;
use warnings;
use Carp qw( confess cluck );
use DBI;

use Bio::Otter::Lace::DB::ColumnAdaptor;
use Bio::Otter::Lace::DB::OTFRequestAdaptor;

use parent qw( Bio::Otter::Log::WithContextMixin );

my(
    %dbh,
    %file,
    %vega_dba,
    %session_slice,
    %ColumnAdaptor,
    %OTFRequestAdaptor,
    %log_context,
    );

sub DESTROY {
    my ($self) = @_;

    delete($dbh{$self});
    delete($file{$self});
    delete($vega_dba{$self});
    delete($session_slice{$self});
    delete($ColumnAdaptor{$self});
    delete($OTFRequestAdaptor{$self});
    delete($log_context{$self});

    return;
}

sub new {
    my ($pkg, %args) = @_;

    my ($home, $client, $log_context) = @args{qw( home client log_context )};

    my $ref = "";
    my $self = bless \$ref, $pkg;
    $self->log_context($log_context);

    unless ($home) {
        $self->logger->logconfess("Cannot create SQLite database without home parameter");
    }

    my $file = "$home/otter.sqlite";
    $self->file($file);

    $self->logger->debug("new() connecting to '$file'");
    $self->init_db($client);

    return $self;
}

sub dbh {
    my ($self, $arg) = @_;

    if ($arg) {
        $dbh{$self} = $arg;
    }
    return $dbh{$self};
}

sub ColumnAdaptor {
    my ($self) = @_;

    return $ColumnAdaptor{$self} ||=
        Bio::Otter::Lace::DB::ColumnAdaptor->new($self->dbh);
}

sub OTFRequestAdaptor {
    my ($self) = @_;

    return $OTFRequestAdaptor{$self} ||=
        Bio::Otter::Lace::DB::OTFRequestAdaptor->new($self->dbh);
}

sub file {
    my ($self, $arg) = @_;

    if ($arg) {
        $file{$self} = $arg;
    }
    return $file{$self};
}

sub vega_dba {
    my ($self) = @_;
    return $vega_dba{$self} if $vega_dba{$self};

    # This pulls in EnsEMBL, so we only do it if required, to reduce the footprint of filter_get &co.
    require Bio::Vega::DBSQL::DBAdaptor;

    $self->_is_loaded('dataset_info') or
        $self->logger->logconfess("Cannot create Vega adaptor until dataset info is loaded");

    my $dbc = Bio::Vega::DBSQL::DBAdaptor->new(
        -driver => 'SQLite',
        -dbname => $file{$self}
        );

    return $vega_dba{$self} = $dbc;
}

sub session_slice {
    my ($self, $ensembl_slice, $dna) = @_;

    my $session_slice = $session_slice{$self};
    return $session_slice if $session_slice;

    $ensembl_slice or
        $self->logger->logconfess("ensembl_slice must be supplied when creating or recovering session_slice");

    # If this is a recovered session we will already have the seq_region in the local DB
    my $slice_adaptor = $self->vega_dba->get_SliceAdaptor;
    my $db_seq_region = $slice_adaptor->fetch_by_region(
        $ensembl_slice->coord_system->name,
        $ensembl_slice->seq_region_name,
        );

    my $contig_seq_region;
    if ($db_seq_region) {
        $self->logger->debug('slice already in sqlite');
    } else {
        $self->logger->debug('creating and storing slice');

        # db_seq_region's coord_system needs to be the one already in the DB.
        my $cs_adaptor = $self->vega_dba->get_CoordSystemAdaptor;
        my $cs_chr    = $cs_adaptor->fetch_by_name($ensembl_slice->coord_system->name,
                                                   $ensembl_slice->coord_system->version);
        my $cs_contig = $cs_adaptor->fetch_by_name('contig', 'OtterLocal');

        # db_seq_region must start from 1
        my $db_seq_region_parameters = {
            %$ensembl_slice,
            coord_system      => $cs_chr,
            start             => 1,
            seq_region_length => $ensembl_slice->end,
        };
        $db_seq_region = Bio::EnsEMBL::Slice->new_fast($db_seq_region_parameters);
        $slice_adaptor->store($db_seq_region);

        my $region_length = $ensembl_slice->end - $ensembl_slice->start + 1;
        my $contig_seq_region_parameters = {
            seq_region_name   => $ensembl_slice->seq_region_name,
            strand            => 1,
            start             => 1,
            end               => $region_length,
            seq_region_length => $region_length,
            coord_system      => $cs_contig,
        };
        $contig_seq_region = Bio::EnsEMBL::Slice->new_fast($contig_seq_region_parameters);
        $slice_adaptor->store($contig_seq_region, \$dna);
    }

    $session_slice = $db_seq_region->sub_Slice($ensembl_slice->start, $ensembl_slice->end);
    if ($contig_seq_region) {
        $slice_adaptor->store_assembly($session_slice, $contig_seq_region);
    }
    return $session_slice{$self} = $session_slice;
}

sub get_tag_value {
    my ($self, $tag) = @_;

    my $sth = $dbh{$self}->prepare(q{ SELECT value FROM otter_tag_value WHERE tag = ? });
    $sth->execute($tag);
    my ($value) = $sth->fetchrow;
    return $value;
}

sub set_tag_value {
    my ($self, $tag, $value) = @_;

    unless (defined $value) {
        $self->logger->logconfess("No value provided");
    }

    my $sth = $dbh{$self}->prepare(q{ INSERT OR REPLACE INTO otter_tag_value (tag, value) VALUES (?,?) });
    $sth->execute($tag, $value);

    return;
}

sub _has_table {
    my ($self, $table) = @_;
    my $sth = $dbh{$self}->table_info(undef, 'main', $table, 'TABLE');
    my $table_info = $sth->fetchrow_hashref;
    return unless $table_info;
    return $table_info->{TABLE_NAME};
}

sub _is_loaded {
    my ($self, $name, $value) = @_;

    my $has_tag_table = $self->_has_table('otter_tag_value');

    if (defined $value) {
        $self->logger->logdie("No otter_tag_value table when setting '$name' tag.") unless $has_tag_table;
        return $self->set_tag_value($name, $value);
    }

    return unless $has_tag_table;
    return $self->get_tag_value($name);
}

sub init_db {
    my ($self, $client) = @_;

    my $file = $self->file or $self->logger->logconfess("Cannot create SQLite database: file not set");

    my $done_file = $file;
    $done_file =~ s{/([^/]+)$}{.done/$1};
    if (!-f $file && -f $done_file) {
        $self->logger->logcluck("Running late?\n  Absent: $file\n  Exists: $done_file");
        # Diagnostics because I saw it after RT395938 Zircon 13e593c10ce4cb1ccdfd362a293a1e940e24e26d
    }

    my $dbh = DBI->connect("dbi:SQLite:dbname=$file", undef, undef, {
        RaiseError => 1,
        AutoCommit => 1,
        sqlite_use_immediate_transaction => 1,
        sqlite_allow_multiple_statements => 1,
        });
    $dbh{$self} = $dbh;

    $self->create_tables($client->get_otter_schema,  'schema_otter')  unless $self->_is_loaded('schema_otter');
    $self->create_tables($client->get_loutre_schema, 'schema_loutre') unless $self->_is_loaded('schema_loutre');

    return 1;
}

sub create_tables {
    my ($self, $schema, $name) = @_;

    $self->logger->debug("create_tables for '$name'");

    my $dbh = $dbh{$self};
    $dbh->begin_work;
    $dbh->do($schema);
    $dbh->commit;

    $self->_is_loaded($name, 1);

    return;
}

my @local_coord_system = (
    {
        coord_system_id => 101,
        species_id      => 1,
        name            => 'contig',
        version         => 'OtterLocal',
        rank            => 101,
        attrib          => 'default_version,sequence_level',
    },
);

my %local_meta = (
    'assembly.mapping.local' => {
        species_id => 1,
        values     => [ 'chromosome:Otter#contig:OtterLocal' ],
    },
);

sub load_dataset_info {
    my ($self, $dataset) = @_;
    return if $self->_is_loaded('dataset_info');

    $self->_is_loaded('schema_loutre') or
        $self->logger->logconfess("Cannot load dataset info: loutre schema not loaded");

    my $dbh = $dbh{$self};

    my $meta_sth = $dbh->prepare(q{ INSERT INTO meta (species_id, meta_key, meta_value) VALUES (?, ?, ?) });
    my $meta_hash = $dataset->meta_hash;

    my @cs_cols = qw(                                        coord_system_id  species_id  name  version  rank  attrib );
    my $cs_sth  = $dbh->prepare(q{ INSERT INTO coord_system (coord_system_id, species_id, name, version, rank, attrib)
                                                     VALUES (?, ?, ?, ?, ?, ?) });
    my $cs_chr  = $dataset->get_db_info_item('coord_system.chromosome');

    my @at_cols = qw(                                       attrib_type_id  code  name  description );
    my $at_sth  = $dbh->prepare(q{ INSERT INTO attrib_type (attrib_type_id, code, name, description)
                                                    VALUES (?, ?, ?, ?) });
    my $at_list = $dataset->get_db_info_item('attrib_type');

    $dbh->begin_work;

    my %meta = ( %$meta_hash, %local_meta );
    while (my ($key, $details) = each %meta) {

        next if $key eq 'assembly.mapping'; # we do our own mapping...
        $key = 'assembly.mapping' if $key eq 'assembly.mapping.local';

        foreach my $value (@{$details->{values}}) {
            $meta_sth->execute($details->{species_id}, $key, $value);
        }
    }

    foreach my $row ($cs_chr, @local_coord_system) {
        $cs_sth->execute(@$row{@cs_cols});
    }

    foreach my $row (@$at_list) {
        $at_sth->execute(@$row{@at_cols});
    }

    $dbh->commit;

    $self->_is_loaded('dataset_info', 1);

    return;
}

# Required by Bio::Otter::Log::WithContextMixin
# (default version is not inside-out compatible!)
sub log_context {
    my ($self, $arg) = @_;

    if ($arg) {
        $log_context{$self} = $arg;
    }

    return $log_context{$self} if $log_context{$self};
    return '-B-O-L-DB unnamed-';
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::DB

=head1 DESCRIPTION

The SQLite db stored in the local AceDatabase directory.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


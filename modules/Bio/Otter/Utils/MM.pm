
### Bio::Otter::Utils::MM

package Bio::Otter::Utils::MM;

use strict;
use warnings;

use DBI;
use Readonly;

=pod

Notes on the MM schema

All cells in the entry.accession columns match
/'^[[:alnum:]]+(-[[:digit:]]+)?\.[[:digit:]]+$'/

=cut

# NB: databases will be searched in the order in which they appear in this list

Readonly my @ALL_DB_CATEGORIES => qw(
    emblnew
    emblrelease
    uniprot
    uniprot_archive
    refseq
);

Readonly my @DEFAULT_DB_CATEGORIES => qw(
    emblnew
    emblrelease
    uniprot
    uniprot_archive
);

Readonly my %CLASS_TO_SOURCE_DB => (
    STD => 'Swissprot',
    PRE => 'TrEMBL',
    ISO => 'Swissprot',  # we don't think TrEMBL can have isoforms
    );

Readonly my %CONNECTION_DEFAULTS => (
    host => 'cbi5d',
    port => 3306,
    user => 'genero',
    name => 'mm_ini',
    );

sub new {
    my ($class, @args) = @_;

    my %options = ( %CONNECTION_DEFAULTS, @args );

    my $self = bless \%options, $class;
    $self->_build_sql;

    return $self;
}

sub _get_connection {
    my ($self, $category) = @_;

    my $dbh;

    # get a connection to mm_ini to look up the correct tables/databases
    my $dsn_mm_ini = "DBI:mysql:".
        "database=".$self->name.
        ";host=".$self->host.
        ";port=".$self->port;

    my $dbh_mm_ini = DBI->connect($dsn_mm_ini, $self->user, '', { 'RaiseError' => 1 });

    if ($category eq 'uniprot_archive') {

        # find the correct host and db to connect to from the connections table

        my $arch_sth = $dbh_mm_ini->prepare(qq{
            SELECT db_name, port, username, host, poss_nodes
            FROM connections
            WHERE is_active = 'yes'
            LIMIT 1
        });

        $arch_sth->execute or die "Couldn't execute statement: " . $arch_sth->errstr;

        my $db_details = $arch_sth->fetchrow_hashref or die "Failed to find active uniprot_archive";

        my $dsn = "DBI:mysql:".
            "database=".$db_details->{'db_name'}.
            ";host=".$db_details->{'host'}.$db_details->{'poss_nodes'}.
            ";port=".$db_details->{'port'};

        $dbh = DBI->connect($dsn, $db_details->{'username'}, '', { 'RaiseError' => 1 });
    }
    else {

        # look for the current and available table for this category from the ini table

        my $ini_sth = $dbh_mm_ini->prepare(qq{
            SELECT database_name
            FROM ini
            WHERE database_category = ?
            AND current = 'yes'
            AND available = 'yes'
        });

        $ini_sth->execute($category) or die "Couldn't execute statement: " . $ini_sth->errstr;

        my $db_details = $ini_sth->fetchrow_hashref or die "Failed to find available db for $category";

        my $dsn = "DBI:mysql:".
            "database=".$db_details->{'database_name'}.
            ";host=".$self->host.
            ";port=".$self->port;

        $dbh = DBI->connect($dsn, $self->user, '', { 'RaiseError' => 1 });
    }

    return $dbh;
}

sub dbh {
    my ($self, $category, $dbh) = @_;

    die "DB category required" unless $category;

    die "Invalid DB category: $category"
      unless grep { /^$category$/ } @ALL_DB_CATEGORIES;

    if ($dbh) {
        die "Not a valid DB handle: " . (ref $dbh) unless ref $dbh && $dbh->isa('DBI::db');
        $self->{_dbhs}->{$category} = $dbh;
    }

    unless ($self->{_dbhs}->{$category}) {
        $self->{_dbhs}->{$category} = $self->_get_connection($category);
    }

    return $self->{_dbhs}->{$category};
}

# We construct a matrix of queries: (plain, with-iso) x (with[exact], like)
#
sub _build_sql {
    my ($self) = @_;

    # May be dangerous to assume that the most recent entries in uniprot_archive
    # will have the biggest entry_id

    my $common_sql = q{
SELECT e.molecule_type
  , e.data_class
  , e.accession_version
  , e.sequence_length
  , GROUP_CONCAT(t.ncbi_tax_id) as taxon_list
  , d.description
%s
WHERE e.accession_version %s
GROUP BY e.entry_id
ORDER BY e.entry_id ASC
};

    my $join_sql = q{
FROM entry e
JOIN description d ON e.entry_id = d.entry_id
JOIN taxonomy    t ON e.entry_id = t.entry_id };

    my $with_sv_sql = sprintf( $common_sql, $join_sql, ' = ?' );
    my $like_sv_sql = sprintf( $common_sql, $join_sql, ' LIKE ?' );

    # For uniprot_archive, we need to use the isoform table for splice variants
    my $join_iso_sql = q{
FROM entry e
JOIN description d ON e.entry_id = d.entry_id
JOIN isoform     i ON e.entry_id = i.isoform_entry_id
JOIN taxonomy    t ON i.parent_entry_id = t.entry_id };

    my $with_sv_iso_sql = sprintf( $common_sql, $join_iso_sql, ' = ?' );
    my $like_sv_iso_sql = sprintf( $common_sql, $join_iso_sql, ' LIKE ?' );

    $self->{_sql} = {
        plain => {
            with => $with_sv_sql,
            like => $like_sv_sql,
        },
        iso => {
            with => $with_sv_iso_sql,
            like => $like_sv_iso_sql,
        },
    };
    return;
}

# Return and cache the statement handle based on db_name, iso-ness and search type
#
sub _sth_for {
    my ($self, $db_name, $iso_key, $search_key) = @_;

    my $dbh = $self->dbh($db_name);

    my $sth = $self->{_sth}->{$dbh}->{$iso_key}->{$search_key};
    return $sth if $sth;

    my $sql = $self->{_sql}->{$iso_key}->{$search_key};
    $sth = $dbh->prepare($sql);
    return $self->{_sth}->{$dbh}->{$iso_key}->{$search_key} = $sth;
}

sub get_accession_types {
    my ($self, $accs) = @_;

    my %acc_hash = map { $_ => 1 } @$accs;
    my $results = {};

    for my $db_name (@DEFAULT_DB_CATEGORIES) {

        my $is_uniprot_archive = ($db_name eq 'uniprot_archive');

        foreach my $name (keys %acc_hash) {

            my ($sth, $search_term);
          SWITCH: for ($name) {
              if ($is_uniprot_archive and $name =~ /-\d+\.\d+$/) {
                  $sth = $self->_sth_for($db_name, 'iso', 'with');
                  $search_term = $name;
                  last SWITCH;
              }
              if ($is_uniprot_archive and $name =~ /-\d+$/) {
                  $sth = $self->_sth_for($db_name, 'iso', 'like');
                  $search_term = "$name.%";
                  last SWITCH;
              }
              if ($name =~ /\.\d+$/) {
                  $sth = $self->_sth_for($db_name, 'plain', 'with');
                  $search_term = $name;
                  last SWITCH;
              }
              # default
              $sth = $self->_sth_for($db_name, 'plain', 'like');
              $search_term = "$name.%";
              last SWITCH;
          }

            $sth->execute($search_term);

          RESULT: while (my ($type, $class, $acc_sv, @extra_info) = $sth->fetchrow) {
              if ($class eq 'EST') {
                  $results->{$name} = [ 'EST', $acc_sv, 'EMBL', @extra_info ];
                  next RESULT;
              }
              if ($type eq 'mRNA') {
                  # Here we return cDNA, which is more technically correct since
                  # both ESTs and cDNAs are mRNAs.
                  $results->{$name} = [ 'cDNA', $acc_sv, 'EMBL', @extra_info ];
                  next RESULT;
              }
              if ($type eq 'protein') {

                  my $source_db = $CLASS_TO_SOURCE_DB{$class};
                  die "Unexpected data class for uniprot entry: $class" unless $source_db;

                  $results->{$name} = [ 'Protein', $acc_sv, $source_db, @extra_info ];
                  next RESULT;
              }
              if ($type eq 'other RNA' or $type eq 'transcribed RNA') {
                  $results->{$name} = [ 'ncRNA', $acc_sv, 'EMBL', @extra_info ];
                  next RESULT;
              }

              warn "Cannot classify '$name': type '$type', class '$class'\n";

          } continue { # RESULT
              delete $acc_hash{$name};
          }
        }

        # We don't need to search any further databases if we've found everything
        last unless keys %acc_hash;
    }

    return $results;
}

sub name {
    my ($self, $name) = @_;
    $self->{name} = $name if $name;
    return $self->{name};
}

sub host {
    my ($self, $host) = @_;
    $self->{host} = $host if $host;
    return $self->{host};
}

sub port {
    my ($self, $port) = @_;
    $self->{port} = $port if $port;
    return $self->{port};
}

sub user {
    my ($self, $user) = @_;
    $self->{user} = $user if $user;
    return $self->{user};
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::MM

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


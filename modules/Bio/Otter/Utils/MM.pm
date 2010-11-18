
### Bio::Otter::Utils::MM

package Bio::Otter::Utils::MM;

use strict;
use warnings;

use DBI;

=pod

Notes on the MM schema

All cells in the entry.accession columns match
/'^[[:alnum:]]+(-[[:digit:]]+)?\.[[:digit:]]+$'/

=cut

# NB: databases will be searched in the order in which they appear in this list
my @DB_CATEGORIES = (
    'emblrelease',
    'uniprot',
    'emblnew',
    'uniprot_archive',

    #'refseq'
);

# pinched from Hum::ClipboardUtils.pm (copied here due to server PERL5LIB issues)
my $magic_evi_name_matcher = qr{
    ([A-Za-z]{2}:)?       # Optional prefix
    (
                          # Something that looks like an accession:
        [A-Z]+\d{5,}      # one or more letters followed by 5 or more digits
        |                 # or, for TrEMBL,
        [A-Z]\d[A-Z\d]{4} # a capital letter, a digit, then 4 letters or digits.
    )
    (\-\d+)?              # Optional VARSPLICE suffix
    (\.\d+)?              # Optional .SV
}x;

sub new {
    my ($class, @args) = @_;

    my $self = bless {}, $class;

    my ($host, $port, $user, $name) = @args;

    $self->host($host || 'cbi3d');
    $self->port($port || 3306);
    $self->user($user || 'genero');
    $self->name($name || 'mm_ini');

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
            SELECT db_name, port, username, host
            FROM connections
            WHERE is_active = 'yes'
            LIMIT 1
        });
        
        $arch_sth->execute or die "Couldn't execute statement: " . $arch_sth->errstr;
        
        my $db_details = $arch_sth->fetchrow_hashref or die "Failed to find active uniprot_archive";
        
        my $dsn = "DBI:mysql:".
            "database=".$db_details->{'db_name'}.
            ";host=".$db_details->{'host'}.
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
      unless grep { /^$category$/ } @DB_CATEGORIES;

    if ($dbh) {
        die "Not a valid DB handle: " . (ref $dbh) unless ref $dbh && $dbh->isa('DBI::db');
        $self->{_dbhs}->{$category} = $dbh;
    }

    unless ($self->{_dbhs}->{$category}) {
        $self->{_dbhs}->{$category} = $self->_get_connection($category);
    }

    return $self->{_dbhs}->{$category};
}

sub get_accession_types {
    my $self = shift;

    my $accs = shift;

    my $sql = '
SELECT molecule_type, data_class, accession_version
FROM entry e, accession a
WHERE e.entry_id = a.entry_id
AND a.accession = ?
';

    my $uniprot_archive_sql = '
SELECT molecule_type, data_class, accession_version
FROM entry
WHERE accession_version LIKE ?
';

    my %acc_hash = ();

    for my $text (@$accs) {
        if ($text =~ /$magic_evi_name_matcher/g) {
            my $prefix = $1 || '*';
            my $acc = $2;
            $acc .= $3 if $3;
            my $sv = $4 || '*';

            $acc_hash{$text} = [ $acc, $sv ];
        }
    }

    my %res = map { $_ => [] } @$accs;

    return \%res unless %acc_hash;

    for my $db (@DB_CATEGORIES) {

        my $archive = $db eq 'uniprot_archive';

        my $query = $archive ? $uniprot_archive_sql : $sql;

        my $sth = $self->dbh($db)->prepare($query);

        for my $key (keys %acc_hash) {

            my ($acc, $sv) = @{ $acc_hash{$key} };

            $acc .= '%' if $archive;    # uniprot_archive accessions have versions appended

            $sth->execute($acc) or die "Couldn't execute statement: " . $sth->errstr;

            if (my ($type, $class, $version) = $sth->fetchrow_array()) {

                my ($db_sv) = $version =~ /.+(\.\d+)/;

                next unless ($sv eq '*') || ($sv eq $db_sv);

                # found an entry, so establish if the type is one we're expecting

                if ($class eq 'EST') {
                    $res{$key} = [ 'EST', "Em:$version" ];
                }
                elsif ($type eq 'mRNA') {
                    $res{$key} = [ 'mRNA', "Em:$version" ];
                }
                elsif ($type eq 'protein') {

                    my $prefix;

                    if ($class eq 'STD') {
                        $prefix = 'Sw';
                    }
                    elsif ($class eq 'PRE') {
                        $prefix = 'Tr';
                    }
                    elsif ($class eq 'ISO') {    # we don't think trembl can have isoforms
                        $prefix = 'Sw';
                    }
                    else {
                        die "Unexpected data class for uniprot entry: $class";
                    }

                    $res{$key} = [ 'Protein', "$prefix:$version" ];
                }
                elsif ($type eq 'other RNA' or $type eq 'transcribed RNA') {
                    $res{$key} = [ 'ncRNA', "Em:$version" ];
                }

                delete $acc_hash{$key};
            }
        }

        last unless %acc_hash;
    }

    return \%res;
}

my $feature_details_sql = {
    description => <<'SQL',
    SELECT d.description
    FROM entry e, description d
    WHERE e.entry_id = d.entry_id
    AND e.accession_version = ?
SQL
    taxon_id => <<'SQL',
    SELECT t.ncbi_tax_id
    FROM entry e, taxonomy t
    WHERE e.entry_id = t.entry_id
    AND e.accession_version = ?
SQL
};

sub get_feature_details {
    my ($self, $feature_name) = @_;

    return unless my ( $accession_version ) =
        $feature_name =~ /\A(?:[[:alpha:]]{2}:)?(.*)\z/;

    my $details = { };

    while ( my ($key, $sql) = each %{$feature_details_sql} ) {
        for my $db (@DB_CATEGORIES) {
            my $sth = $self->dbh($db)->prepare($sql);
            $sth->execute($accession_version);
            next unless my ($value) = $sth->fetchrow_array();
            $details->{$key} = $value;
            last;
        }
    }

    return $details;
}

sub name {
    my ($self, $name) = @_;
    $self->{_name} = $name if $name;
    return $self->{_name};
}

sub host {
    my ($self, $host) = @_;
    $self->{_host} = $host if $host;
    return $self->{_host};
}

sub port {
    my ($self, $port) = @_;
    $self->{_port} = $port if $port;
    return $self->{_port};
}

sub user {
    my ($self, $user) = @_;
    $self->{_user} = $user if $user;
    return $self->{_user};
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::MM

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk


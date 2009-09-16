
### Bio::Otter::Utils::MM

package Bio::Otter::Utils::MM;

use strict;
use warnings;

use DBI;
use Data::Dumper;

use CGI::Carp qw(fatalsToBrowser);

# NB: databases will be searched in the order in which they appear in this list
my @DB_CATEGORIES = (	'emblrelease',
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
    my ( $class, @args ) = @_;

    my $self = bless {}, $class;

	my ( $host , $port , $user, $name ) = @args;

    $self->host($host || 'cbi3d');
    $self->port($port || 3306);
    $self->user($user || 'genero');
    $self->name($name || 'mm_ini');

    return $self;
}

sub _get_connection {
	my ( $self, $category ) = @_;

	my $dbh;

	if ($category eq 'uniprot_archive') {
		my $dsn = "DBI:mysql:host=".$self->host.":uniprot_archive";
		$dbh = DBI->connect( $dsn, $self->user, '',{ 'RaiseError' => 1 } );
	}
	else {
		# look up the current version
		my $dsn_mm_ini = "DBI:mysql:host=".$self->host.":".$self->name;
		my $dbh_mm_ini = DBI->connect( $dsn_mm_ini, $self->user, '',{ 'RaiseError' => 1 } );
		my $db;
		my $query = q(	SELECT database_name FROM ini
					 	WHERE database_category = ?
					 	AND current = 'yes'
					 	AND available = 'yes' );
		my $ini_sth = $dbh_mm_ini->prepare($query);
		$ini_sth->execute($category) or die "Couldn't execute statement: " . $ini_sth->errstr;
		while(my $hash = $ini_sth->fetchrow_hashref()) {
			$db = $hash->{'database_name'};
		}
		$ini_sth->finish();
		my $dsn = "DBI:mysql:host=".$self->host.":$db";
		$dbh = DBI->connect( $dsn, $self->user, '',{ 'RaiseError' => 1 } );
	}
	return $dbh;
}

sub dbh {
	my ( $self, $category, $dbh ) = @_;

	die "DB category required" unless $category;

	die "Invalid DB category: $category" unless
		grep {/^$category$/} @DB_CATEGORIES;

	if ($dbh) {
		eval { $dbh->isa('DBI::db') };
		die "Not a valid DB handle: ".(ref $dbh) if $@;
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

	my $sql = '	SELECT molecule_type, data_class, accession_version
				FROM entry e, accession a
				WHERE e.entry_id = a.entry_id
				AND a.accession = ? ';

	my $uniprot_archive_sql = ' SELECT molecule_type, data_class, accession_version
        						FROM entry
        						WHERE accession_version LIKE ?';

	my %acc_hash = ();

	for my $text (@$accs) {
       	if ($text =~ /$magic_evi_name_matcher/g) {
       		my $prefix = $1 || '*';
        	my $acc    = $2;
            $acc      .= $3 if $3;
       		my $sv     = $4 || '*';

       		$acc_hash{$text} = [$acc, $sv];
	   	}
	}

	my %res = map {$_ => []} @$accs;

	return \%res unless %acc_hash;

	for my $db (@DB_CATEGORIES) {

        my $archive = $db eq 'uniprot_archive';

       	my $query = $archive ? $uniprot_archive_sql : $sql;

		my $sth = $self->dbh($db)->prepare($query);

		for my $key (keys %acc_hash) {

			my ($acc, $sv) = @{ $acc_hash{$key} };

			$acc .= '%' if $archive; # uniprot_archive accessions have versions appended

			$sth->execute($acc) or die "Couldn't execute statement: " . $sth->errstr;

			if (my ($type, $class, $version) = $sth->fetchrow_array()) {

				my ($db_sv) = $version =~ /.+(\.\d+)/;

				next unless ($sv eq '*') || ($sv eq $db_sv);

				# found an entry, so establish if the type is one we're expecting

				if ($class eq 'EST') {
					$res{$key} = ['EST', "Em:$version"];
				}
				elsif ($type eq 'mRNA') {
					$res{$key} = ['mRNA', "Em:$version"];
				}
				elsif ($type eq 'other RNA') {
					$res{$key} = ['ncRNA', "Em:$version"];
				}
				elsif ($type eq 'protein') {

					my $prefix;

					if ($class eq 'STD') {
						$prefix = 'Sw';
					}
					elsif ($class eq 'PRE') {
						$prefix = 'Tr';
					}
					elsif ($class eq 'ISO') { # we don't think trembl can have isoforms
						$prefix = 'Sw';
					}
					else {
						die "Unexpected data class for uniprot entry: $class";
					}

					$res{$key} = ['Protein', "$prefix:$version"];
				}

				delete $acc_hash{$key};
			}
		}

		last unless %acc_hash;
	}

	return \%res;
}

sub name {
    my ( $self, $name ) = @_;
    $self->{_name} = $name if $name;
    return $self->{_name};
}

sub host {
    my ( $self, $host ) = @_;
    $self->{_host} = $host if $host;
    return $self->{_host};
}

sub port {
    my ( $self, $port ) = @_;
    $self->{_port} = $port if $port;
    return $self->{_port};
}

sub user {
    my ( $self, $user ) = @_;
    $self->{_user} = $user if $user;
    return $self->{_user};
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::MM

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk


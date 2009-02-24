package Bio::Otter::Utils::MM;

use strict;
use Hum::ClipboardUtils '$magic_evi_name_matcher';
use DBI;
use Data::Dumper;

my @DB_CATEGORIES = (	'emblrelease', 
						'uniprot', 
						'emblnew',
						#'refseq'
					);

sub new {
    my ( $class, @args ) = @_;
    
    my $self = bless {}, $class;

	my ( $host , $port , $user, $name ) = @args;
	
    $self->host($host || 'cbi3');
    $self->port($port || 3306);
    $self->user($user || 'genero');
    $self->name($name || 'mm_ini');
    $self->{_dbhs} = { map { $_ => undef } @DB_CATEGORIES };

    return $self;
}

sub _get_connection {
	my ( $self, $category ) = @_;
	
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
	my $dbh = DBI->connect( $dsn, $self->user, '',{ 'RaiseError' => 1 } );

	return $dbh;
}

sub dbh {
	my ( $self, $category, $dbh ) = @_;
	
	die "DB category required" unless $category;
	
	die "Invalid DB category: $category" unless 
		grep {/^$category$/} keys %{ $self->{_dbhs} };
	
	if ($dbh) {
		die "Not a valid DB handle: ".(ref $dbh) unless ref $dbh eq 'DBI::db';
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
	
	my $sql = '	SELECT molecule_type, data_class 
				FROM entry e, accession a
				WHERE e.entry_id = a.entry_id
				AND a.accession = ? ';
	
	my %acc_hash = map {$_ => (/$magic_evi_name_matcher/g ? $2.($3?$3:'') : '') } @$accs; 

	my %res = map {$_ => ''} @$accs;

	for my $db (keys %{ $self->{_dbhs} }) {
        	
        # try each database in turn
        	
		my $sth = $self->dbh($db)->prepare($sql);
			
		for my $key (keys %acc_hash) {
				
			next unless $acc_hash{$key};
			
			$sth->execute($acc_hash{$key}) or die "Couldn't execute statement: " . $sth->errstr;
			
			if (my ($type, $class) = $sth->fetchrow_array()) {
						
				# found an entry, so establish if the type is one we're expecting
						
				if ($class eq 'EST') {
					$res{$key} = 'EST';
				}
				elsif ($type eq 'mRNA' and $class eq 'STD') {
					$res{$key} = 'mRNA';
				}
				elsif ($type eq 'protein') {
					$res{$key} = 'Protein';
				}
				#else {$res{$key} = "(Unrecognised: $type)";}
				
				delete $acc_hash{$key};
			}
		}
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

package Bio::Otter::DBSQL::SimpleBindingAdaptor;

use DBI;
# use strict;

sub connect_with_params {
	my %params = @_;

	my $datasource = "DBI:mysql:$params{-DBNAME}:$params{-HOST}:$params{-PORT}";
	my $username   = $params{-USER};
	my $password   = $params{-PASS} || '';

	return DBI->connect($datasource, $username, $password, { RaiseError => 1 });
}

sub new {
    my $pkg            = shift @_;
    my %connect_params = @_;

    my $dbh = connect_with_params(%connect_params);

    my $self = bless {
        '_connect_param_hp' => \%connect_params,
        '_dbh'              => $dbh,
    }, $pkg;

    return $self;
}

sub fetch_into_hash {
    my ($self, $table_name, $field_name, $field_hp, $class, $thehash) = @_;

    if(%$thehash) {
        my $sql_statement =
              'SELECT '
            . join(', ', $field_name, keys %$field_hp)
            . ' FROM '
            . $table_name
            . ' WHERE '
            . $field_name
            . ' IN ('
            . join(', ', map { "'$_'" }  keys %$thehash)
            . ");\n";

        my $sth = $self->{_dbh}->prepare($sql_statement);
        $sth->execute();
        
        my $bound_name;
        my %bound_hash;
        $sth->bind_columns( \$bound_name, map { \$bound_hash{$_} } values %$field_hp );

        while ($sth->fetch) {
            $thehash->{$bound_name} = bless {
                map { ($_ => $bound_hash{$_}) } values %$field_hp
            } , $class;
        }
        $sth->finish();
    } else {
        print STDERR "No hit names to find the ${class}'s for\n";
    }

    return $thehash;
}

sub DESTROY {
    my $self = shift @_;

    $self->{_dbh}->disconnect();
}

1;


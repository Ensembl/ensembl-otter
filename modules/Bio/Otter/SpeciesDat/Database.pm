package Bio::Otter::SpeciesDat::Database;

use strict;
use warnings;

use Bio::Otter::SpeciesDat::DataSet;


=head1 NAME

Bio::Otter::SpeciesDat::Database - spec for one database server

=head1 DESCRIPTION

Objects of this class point to a database server, on the expectation
that we have a few of these with many named databases inside.

=head1 METHODS

=cut


# Instantiate through Bio::Otter::Server::Config->databases()
sub new {
    my ($pkg, $name, %params) = @_;
    my $self = { _name => $name, _params => \%params };
    bless $self, $pkg;

    if ($params{-alias}) {
        # Aliases are resolved by new_many_from_dbspec
        die "New $pkg for name=$name has -alias=$params{-alias}, should have nothing else"
          if keys %params > 1;
    } else {
        # Any other entry has to have the expected keys
        my %bad = %params;
        delete @bad{qw{ -host -port -user -pass }};
        my @bad = sort keys %bad;
        die "New $pkg for name=$name contains bad keys (@bad) - should point just to a server"
          if @bad;
        my @miss = grep { !defined $params{$_} } qw{ -host -port -user };
        die "New $pkg for name=$name has missing keys (@miss)"
          if @miss;
    }

    return $self;
}

sub new_many_from_dbspec {
    my ($pkg, $dbspec) = @_;
    my %out = map {( $_ => $pkg->new($_ => %{ $dbspec->{$_} }) )} keys %$dbspec;

    # resolve aliases, if any
    my %replace;
    while (my ($k, $obj) = each %out) {
        my $al = $obj->_params->{-alias};
        next unless $al;
        my $r = $replace{$k} = $out{$al};
        die "Alias $k --> $al points nowhere" unless $r;
        die "Alias $k --> $al points to another alias"
          # not interested in chasing out the loops
          if $r->_params->{-alias};
    }
    @out{ keys %replace } = values %replace if keys %replace;

    return \%out;
}


=head2 name()

Return the name under which this database server is stored in the
C<databases.yaml> file.

=cut

sub name {
    my ($self) = @_;
    return $self->{_name};
}

sub _params {
    my ($self) = @_;
    return $self->{_params};
}

sub _init_accessors {
    my ($pkg) = @_;
    foreach my $method (qw( host port user pass )) {
        my $key = "-$method";
        my $code = sub {
            my ($self) = @_;
            return $self->_params->{$key};
        };
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{"$pkg\::$method"} = $code;
    }
    return;
}

sub _pass_maybe {
    my ($self, $key) = @_;
    my $p = $self->pass;
    return defined $p ? ($key => $p) : ();
}


=head2 spec_DBI($dbname, $attr)

Return a list suitable for use in C<< DBI->connect(@list) >>.

This will reach the database schema named C<$dbname> if given, or
otherwise to connect C<USE>ing no particular schema.

C<$attr> is copied to use as the last element of the output @list and
will have the defaults C<< { RaiseError => 1, AutoCommit => 1,
PrintError => 0 } >> merged into it after copy.

=cut

sub spec_DBI {
    my ($self, $dbname, $attr_in) = @_;
    my %attr = (RaiseError => 1, AutoCommit => 1, PrintError => 0);
    while (my ($k, $v) = each %$attr_in) {
        $attr{$k} = $v;
    }
    my $dsn = sprintf('DBI:mysql:host=%s;port=%s', $self->host, $self->port);
    $dsn = "$dsn;database=$dbname" if defined $dbname;
    return ($dsn, $self->user, $self->pass, \%attr);
}


=head2 spec_DataSet($name => $dbname)

Return a L<Bio::Otter::SpeciesDat::DataSet> object derived from this
server and the schema C<$dbname>.

=cut

sub spec_DataSet {
    my ($self, $name, $dbname) = @_;
    return Bio::Otter::SpeciesDat::DataSet->new
      ($name,
       HOST => $self->host,
       PORT => $self->port,
       USER => $self->user,
       $self->_pass_maybe('PASS'),
       DBNAME => $dbname);
}

__PACKAGE__->_init_accessors;

1;

__END__

=head1 CAVEATS

Currently we assume all are L<DBD::mysql>.  If ever they were not,
this would be the place to add a "driver" key+value.

Currently you can't get a L<DBI> or Ensembl DBAdaptor from this class.
It was intended to be used via L<Bio::Otter::SpeciesDat>.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


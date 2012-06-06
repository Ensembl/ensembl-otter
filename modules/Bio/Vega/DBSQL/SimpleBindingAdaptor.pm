package Bio::Vega::DBSQL::SimpleBindingAdaptor;

use strict;
use warnings;

use DBI;

sub new {
    my ($pkg, $dbc) = @_;


    my $self = {
        '_dbc'  => $dbc,
    };

    bless $self, $pkg;

    return $self;
}

sub fetch_into_hash {
    my ($self, $table_name, $field_name, $field_hp, $class, $thehash) = @_;

    die "'require $class' failed"
        unless eval "require $class"; ## no critic (BuiltinFunctions::ProhibitStringyEval)

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

        my $sth = $self->{_dbc}->prepare($sql_statement);
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
        warn "No hit names to find the ${class}'s for\n";
    }

    return $thehash;
}

sub DESTROY {
    my ($self) = @_;

    # $self->{_dbc}->disconnect();

    return;
}

1;

__END__

=head1 NAME - Bio::Vega::DBSQL::SimpleBindingAdaptor;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


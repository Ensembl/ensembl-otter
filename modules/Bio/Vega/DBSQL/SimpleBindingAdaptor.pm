=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Bio::Vega::DBSQL::SimpleBindingAdaptor;

use strict;
use warnings;

use DBI;

use Bio::Otter::Utils::RequireModule qw(require_module);

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

    require_module($class);

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



package Bio::Otter::SpeciesDat::DataSet;

use strict;
use warnings;

sub new {
    my ($pkg, $name, $params) = @_;
    my $new = {
        _name   => $name,
        _params => $params,
    };
    bless $new, $pkg;
    return $new;
}

sub name {
    my ($self) = @_;
    return $self->{_name};
}

sub params {
    my ($self) = @_;
    return $self->{_params};
}

sub otter_dba {
    my ($self) = @_;
    return $self->{_otter_dba} ||=
        $self->_otter_dba;
}

sub _otter_dba {
    my ($self) = @_;

    my $name   = $self->name;
    my $params = $self->params;

    my $dbname = $params->{DBNAME};
    die "Failed opening otter database [No database name]" unless $dbname;

    require Bio::Vega::DBSQL::DBAdaptor;
    require Bio::EnsEMBL::DBSQL::DBAdaptor;

    my $odba;
    die "Failed opening otter database [$@]" unless eval {
        $odba = Bio::Vega::DBSQL::DBAdaptor->new(
            -host    => $params->{HOST},
            -port    => $params->{PORT},
            -user    => $params->{USER},
            -pass    => $params->{PASS},
            -dbname  => $dbname,
            -group   => 'otter',
            -species => $name,
            );
        1;
    };

    my $dna_dbname = $params->{DNA_DBNAME};
    if ($dna_dbname) {
        my $dnadb;
        die "Failed opening dna database [$@]" unless eval {
            $dnadb = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                -host    => $params->{DNA_HOST},
                -port    => $params->{DNA_PORT},
                -user    => $params->{DNA_USER},
                -pass    => $params->{DNA_PASS},
                -dbname  => $dna_dbname,
                -group   => 'dnadb',
                -species => $name,
                );
            1;
        };
        $odba->dnadb($dnadb);
    }

    return $odba;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


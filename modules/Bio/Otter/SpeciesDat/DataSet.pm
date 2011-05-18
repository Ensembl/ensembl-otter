
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

sub default_assembly {
    my ($self, $dba) = @_;

    my ($asm_def) = @{ $dba->get_MetaContainer()->list_value_by_key('assembly.default') };

    return $asm_def || 'UNKNOWN';
}

sub pipeline_dba {
    my ($self) = @_;
    return $self->satellite_dba('pipeline_db_head');
}

sub satellite_dba {
    my ($self, $metakey) = @_;

    # check for a cached dba
    my $dba_cached = $self->{_sdba}{$metakey};
    return $dba_cached if $dba_cached;

    # get and check the options
    my $options = $self->satellite_dba_options($metakey);
    die "metakey '$metakey' is not defined" unless $options;

    # create the adaptor
    my $dba = $self->satellite_dba_make($metakey, "Bio::EnsEMBL::DBSQL::DBAdaptor", $options);

    # create the variation database (if there is one)
    my $vdba = $self->variation_satellite_dba_make("${metakey}_variation");
    $vdba->dnadb($dba) if $vdba;

    return $dba;
}

sub variation_satellite_dba_make {
    my ($self, $metakey) = @_;

    # check for a cached dba
    my $dba = $self->{_sdba}{$metakey};
    return $dba if $dba;

    # get and check the options
    my $options = $self->satellite_dba_options($metakey);
    return unless $options;

    # create the adaptor
    $dba = $self->satellite_dba_make($metakey, "Bio::EnsEMBL::Variation::DBSQL::DBAdaptor", $options);

    return $dba;
}

sub satellite_dba_make {
    my ($self, $metakey, $adaptor_class, $options) = @_;

    my @options;
    {
        ## no critic(BuiltinFunctions::ProhibitStringyEval)
        @options = eval $options;
    }
    die "Error evaluating '$options' : $@" if $@;

    my %anycase_options = (
         -group     => $metakey,
         -species   => $self->name,
        @options,
    );

    my %uppercased_options = ();
    while( my ($k,$v) = each %anycase_options) {
        $uppercased_options{uc($k)} = $v;
    }

    eval "require $adaptor_class" ## no critic (BuiltinFunctions::ProhibitStringyEval)
        or die "'require $adaptor_class' failed";
    my $dba = $adaptor_class->new(%uppercased_options);
    die "Couldn't connect to '$metakey' satellite db"
        unless $dba;

    warn "... with parameters: ".join(', ', map { "$_=".$uppercased_options{$_} } keys %uppercased_options )."\n";

    $self->{_sdba}{$metakey} = $dba;

    return $dba;
}

sub satellite_dba_options {
    my ($self, $metakey) = @_;

    my $meta_container = $self->otter_dba->get_MetaContainer;
    my ($options) = @{ $meta_container->list_value_by_key($metakey) };

    return $options;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


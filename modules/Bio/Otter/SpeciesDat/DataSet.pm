=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


package Bio::Otter::SpeciesDat::DataSet;

use strict;
use warnings;
use Carp;

use Try::Tiny;

use Bio::Otter::Server::Config;
use Bio::Otter::Utils::RequireModule qw(require_module);


=head1 NAME

Bio::Otter::SpeciesDat::DataSet - represent a species, server side

=head1 METHODS

=head2 new

This class is not intended for construction directly.

(For a counter-example, see F<xt/db/assembly_check.t> which imagines
up a TEST dataset.)

Use L<Bio::Otter::Server::Config/SpeciesDat>, or where access control
is needed L<Bio::Otter::Server::Support::Web/allowed_datasets>, or if
you have a writable dataset L</clone_readonly>.

(Immediate callers C<catch> to put debug info in the error text.)

=head2 Property read accessors

Methods are provided to read (not write) all the usual properties

 ALIAS READONLY
 HOST     PORT     USER     PASS     DBSPEC     DBNAME
 DNA_HOST DNA_PORT DNA_USER DNA_PASS DNA_DBSPEC DNA_DBNAME

=cut

sub new {
    my ($pkg, $name, $params) = @_;
    my %params = %{ $params };
    $params{READONLY} = 0 unless exists $params{READONLY};
    my $new = {
        _name   => $name,
        _params => \%params,
    };
    bless $new, $pkg;
    $new->_init_fillin;
    return $new;
}


=head2 clone_readonly()

Returns a readonly dataset.

The caller I<should> prevent writing by inspecting L</READONLY>, but
also this returned configuration should provide alternative database
parameters (for slave or readonly user).

=cut

sub clone_readonly {
    my ($called) = @_;
    die "Need an object" unless ref($called);
    return $called if $called->READONLY;
    my $name = $called->name;

    # Ugly because I copied BOS:Database props instead of holding a ref
    my %param = (READONLY => 1,
                 ALIAS => $called->ALIAS,
                 DBNAME => $called->DBNAME,
                 DNA_DBNAME => $called->DNA_DBNAME);
    foreach my $spec (qw( DBSPEC DNA_DBSPEC )) {
        my $rw_spec = $called->$spec;
        my $db = Bio::Otter::Server::Config->Database($rw_spec);
        $param{$spec} = $db->ro_dbspec
          or die "Cannot clone_readonly for dataset $name using $spec=$rw_spec - add databases.yaml {dbspec}{$rw_spec}{ro_dbspec}";
    }

    my $pkg = ref($called);
    my $self = try {
        $pkg->new($name, \%param);
    } catch {
        croak "Dataset $name clone_readonly: $_";
    };
    return $self;
}


=head2 name()

Name of dataset.

=cut

sub name {
    my ($self) = @_;
    return $self->{_name};
}


=head2 ds_all_params()

Return a (copied) hashref of all configured and derived key/value
pairs.

This is useful for access as a collection, but if you need specific
properties use the read accessors like C<HOST>, C<READONLY> or
C<DNA_DBSPEC> to prevent silent typos.

=cut

sub ds_all_params {
    my ($self) = @_;
    my %out = %{ $self->_params };
    return \%out;
}
sub params { # useful, but too easy to mis-key and too hard to grep for
    my ($self) = @_;
    carp '$BOSDataSet->params->{KEY} deprecated'; # use ->KEY or ->ds_all_params
    return $self->ds_all_params;
}

# Internal.  We may change the set of keys held.
sub _params {
    my ($self) = @_;
    return $self->{_params};
}

# Populate HOST,PORT,USER,PASS in-place from DBSPEC and databases.yaml
sub _init_fillin {
    my ($self) = @_;
    my $p = $self->_params;
    my $nm = $self->name;
    foreach my $prefix ('', 'DNA_') {
        my $speckey = "${prefix}DBSPEC";
        my $dbspec = $p->{$speckey};
        die "no $speckey - old species.dat ?" unless $dbspec;
        my $db = Bio::Otter::Server::Config->Database($dbspec);

        my %info =
          ("${prefix}HOST" => $db->host,
           "${prefix}PORT" => $db->port,
           "${prefix}USER" => $db->user,
           $db->pass_maybe("${prefix}PASS"));

        # Replace into our params
        @$p{ keys %info } = values %info;
    }
    return;
}


=head2 otter_dba()

Return cached Otter DBA.

=cut

sub otter_dba {
    my ($self) = @_;
    return $self->{_otter_dba} ||=
        $self->_otter_dba;
}

sub _otter_dba {
    my ($self) = @_;
    my $name   = $self->name;

    die "Failed opening otter database [No database name]" unless $self->DBNAME;

    require Bio::Vega::DBSQL::DBAdaptor;
    require Bio::EnsEMBL::DBSQL::DBAdaptor;

    my $odba;
    try {
        $odba = Bio::Vega::DBSQL::DBAdaptor->new(
            -host    => $self->HOST,
            -port    => $self->PORT,
            -user    => $self->USER,
            -pass    => $self->PASS,
            -dbname  => $self->DBNAME,
            -group   => 'otter',
            -species => $name,
            );
    }
    catch { die "Failed opening otter database [$_]"; };

    if ($self->DNA_DBNAME) {
        my $dnadb;
        try {
            $dnadb = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                -host    => $self->DNA_HOST,
                -port    => $self->DNA_PORT,
                -user    => $self->DNA_USER,
                -pass    => $self->DNA_PASS,
                -dbname  => $self->DNA_DBNAME,
                -group   => 'dnadb',
                -species => $name,
                );
        }
        catch { die "Failed opening dna database [$_]"; };
        $odba->dnadb($dnadb);
    }

    return $odba;
}


=head2 pipeline_dba(@opt)

With no options, you get a read-only vanilla-ensembl DBAdaptor.
Pass opts 'pipe' and 'rw' to get a read-write B:E:Pipeline::Finished:DBA

=cut

sub pipeline_dba {
    my ($self, @opt) = @_;

    my %opt; @opt{@opt} = (1) x @opt;

    my $adaptor_class =
      (delete $opt{pipe}
       ? 'Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor'
       : 'Bio::Vega::DBSQL::DBAdaptor');

    my $meta_key =
      (delete $opt{rw}
       ? 'pipeline_db_rw_head'
       : 'pipeline_db_head');

    if (my @unk = sort keys %opt) {
        croak "Unknown options (@unk) to pipeline_dba";
    }

    return $self->satellite_dba($meta_key, $adaptor_class);
}


=head2 satellite_dba($metakey, $adaptor_class)

Return DBAdaptor for any satellite database.

=cut

sub satellite_dba {
    my ($self, $metakey, $adaptor_class) = @_;
    $adaptor_class ||= "Bio::EnsEMBL::DBSQL::DBAdaptor";

    # check for a cached dba
    my $dba_cached = $self->{_sdba}{$metakey}{$adaptor_class};
    return $dba_cached if $dba_cached;

    # create the adaptor
    my $dba = $self->_satellite_dba_make($metakey, $adaptor_class);
    die "metakey '$metakey' is not defined" unless $dba;

    # create the variation database (if there is one)
    my $vdba = $self->_variation_satellite_dba("${metakey}_variation");
    $vdba->dnadb($dba) if $vdba;

    return $dba;
}

sub _variation_satellite_dba {
    my ($self, $metakey) = @_;
    my $adaptor_class = "Bio::EnsEMBL::Variation::DBSQL::DBAdaptor";

    # check for a cached dba
    my $dba_cached = $self->{_sdba}{$metakey}{$adaptor_class};
    return $dba_cached if $dba_cached;

    # create the adaptor
    my $dba = $self->_satellite_dba_make($metakey, $adaptor_class);

    return unless $dba; # (there isn't one)
    return $dba;
}

sub _satellite_dba_make {
    my ($self, $metakey, $adaptor_class) = @_;

    my $options = $self->_satellite_dba_options($metakey);
    return unless $options;

    my @options;
    {
        ## no critic (BuiltinFunctions::ProhibitStringyEval,Anacode::ProhibitEval)
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

    require_module($adaptor_class);
    my $dba = $adaptor_class->new(%uppercased_options);
    die "Couldn't connect to '$metakey' satellite db"
        unless $dba;
    if ((my $cls = ref($dba)) ne $adaptor_class) {
        # DBAdaptor class is caching(?) these somewhere.  Probably
        # don't need it to work right, but avoid silent surprises.
        die "Instantiation of '$adaptor_class' failed, got a '$cls'";
    }

    $self->{_sdba}{$metakey}{$adaptor_class} = $dba;

    return $dba;
}

sub _satellite_dba_options {
    my ($self, $metakey) = @_;

    my $meta_container = $self->otter_dba->get_MetaContainer;
    my ($options) = @{ $meta_container->list_value_by_key($metakey) };

    return $options;
}


sub _init {
    my ($pkg) = @_;
    my @reader =
      (qw( ALIAS READONLY ),
       qw( HOST     PORT     USER     PASS     DBSPEC     DBNAME ),
       qw( DNA_HOST DNA_PORT DNA_USER DNA_PASS DNA_DBSPEC DNA_DBNAME ));

    foreach my $method (@reader) {
        my $code = sub {
            my ($self, @junk) = @_;
            confess "no write" if @junk;
            return $self->_params->{$method};
        };
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{"$pkg\::$method"} = $code;
    }
    return 1;
}

__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


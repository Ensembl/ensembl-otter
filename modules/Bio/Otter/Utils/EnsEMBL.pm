
### Bio::Otter::Utils::EnsEMBL

package Bio::Otter::Utils::EnsEMBL;

use strict;
use warnings;

use Readonly;

Readonly my $ENSEMBL_METAKEY => 'ensembl_core_db_head';

sub new {
    my ($class, @args) = @_;
    my $self = bless {}, $class;

    $self->_dataset(@args);
    return $self;
}

sub ensembl_dba {
    my $self = shift;
    return $self->_dataset->satellite_dba($ENSEMBL_METAKEY);
}

sub stable_id_from_otter_id {
    my ($self, $otter_id) = @_;

    my $external_db = undef;    # all external DBs

    my $dba = $self->ensembl_dba;
    my $object_type = 'Transcript'; # FIXME
    my $object_adaptor = $dba->get_adaptor($object_type);

    my $objects = $object_adaptor->fetch_all_by_external_name($otter_id, $external_db);

    my %results_by_name;
    foreach my $object ( @$objects ) {
        ++$results_by_name{$object->stable_id};
    }

    my @stable_ids = keys %results_by_name;
    warn('More than one stable_id found') if scalar(@stable_ids) > 1;

    return $stable_ids[0];
}

sub _dataset {
    my ($self, @args) = @_;
    ($self->{'_dataset'}) = @args if @args;
    my $_dataset = $self->{'_dataset'};
    return $_dataset;
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::EnsEMBL

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


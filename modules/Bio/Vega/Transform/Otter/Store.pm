
### Bio::Vega::Transform::Otter::Store

package Bio::Vega::Transform::Otter::Store;

use strict;
use warnings;

use NEXT;

use parent qw( Bio::Vega::Transform::Otter Bio::Otter::Log::WithContextMixin );

my (
    %vega_dba,
    %log_context,
    );

sub DESTROY {
    my ($self) = @_;

    delete $vega_dba{$self};
    delete($log_context{$self});

    return $self->NEXT::DESTROY;
}

# FIXME: log_context setup

sub vega_dba {
    my ($self, @args) = @_;
    ($vega_dba{$self}) = @args if @args;
    my $vega_dba = $vega_dba{$self};
    return $vega_dba;
}

sub store {
    my ($self, $dna) = @_;

    my $vega_dba = $self->vega_dba;

    my $cs_a = $self->vega_dba->get_CoordSystemAdaptor;
    foreach my $cs_type ( qw( Chr Clone Contig ) ) {
        my $get_set = "get_set_${cs_type}CoordSystem";
        my $coord_system = $self->$get_set;
        unless ($coord_system->is_stored($vega_dba)) {
            $cs_a->store($coord_system);
        }
    }

    my $slice = $self->get_ChromosomeSlice;
    my $db_slice = $self->slice_stored_if_needed($slice, $dna);

    my $reattach = ($db_slice != $slice);

    my $gene_a = $vega_dba->get_GeneAdaptor;
    foreach my $gene ( @{$self->get_Genes} ) {
        if ($reattach) {
            $self->_reattach_gene($gene, $db_slice);
        }
        $gene_a->store($gene);
    }

    return;
}

sub slice_stored_if_needed {
    my ($self, $region_slice, $dna) = @_;

    my $vega_dba = $self->vega_dba;
    my $slice_adaptor = $vega_dba->get_SliceAdaptor;

    my $db_seq_region = $slice_adaptor->fetch_by_region(
        $region_slice->coord_system->name,
        $region_slice->seq_region_name,
        );

    my $contig_seq_region;
    if ($db_seq_region) {
        $self->logger->debug('slice already in sqlite');
    } else {
        $self->logger->debug('creating and storing slice');

        # db_seq_region's coord_system needs to be the one already in the DB.
        my $cs_adaptor = $vega_dba->get_CoordSystemAdaptor;
        my $cs_chr    = $cs_adaptor->fetch_by_name($region_slice->coord_system->name,
                                                   $region_slice->coord_system->version);
        my $cs_contig = $cs_adaptor->fetch_by_name('contig', 'OtterLocal');

        # db_seq_region must start from 1
        my $db_seq_region_parameters = {
            %$region_slice,
            coord_system      => $cs_chr,
            start             => 1,
            seq_region_length => $region_slice->end,
        };
        $db_seq_region = Bio::EnsEMBL::Slice->new_fast($db_seq_region_parameters);
        $slice_adaptor->store($db_seq_region);

        # Replace $region_slice with one connected to the database
        $region_slice = $db_seq_region->sub_Slice($region_slice->start, $region_slice->end);

        my $region_length = $region_slice->end - $region_slice->start + 1;
        my $contig_seq_region_parameters = {
            seq_region_name   => $region_slice->seq_region_name,
            strand            => 1,
            start             => 1,
            end               => $region_length,
            seq_region_length => $region_length,
            coord_system      => $cs_contig,
        };
        $contig_seq_region = Bio::EnsEMBL::Slice->new_fast($contig_seq_region_parameters);
        $slice_adaptor->store($contig_seq_region, \$dna);

        $slice_adaptor->store_assembly($region_slice, $contig_seq_region);
    }

    return $region_slice;
}

# FIXME - dup with B:O:ServerAction::Region->_write_region_exclusive
sub _reattach_gene {
    my ($self, $gene, $db_slice) = @_;

    $gene->slice($db_slice);

    foreach my $tran (@{ $gene->get_all_Transcripts }) {
        $tran->slice($db_slice);
    }

    foreach my $exon (@{ $gene->get_all_Exons }) {
        $exon->slice($db_slice);
    }

    return $gene;
}

# Overrides parent to check DB first
#
sub get_set_CoordSystem {
    my ($self, $cs_type) = @_;

    my $get    = "get_${cs_type}CoordSystem";

    my $coord_system = $self->$get;
    return $coord_system if $coord_system;

    my $create = "create_${cs_type}CoordSystem";
    my $set    = "set_${cs_type}CoordSystem";

    my $template_cs = $self->$create;

    # First check we don't already have it
    my $cs_a = $self->vega_dba->get_CoordSystemAdaptor;
    $coord_system = $cs_a->fetch_by_name($template_cs->name, $template_cs->version);

    # If not, return the template - it'll get stored later if needed
    $coord_system = $template_cs unless $coord_system;

    return $self->$set($coord_system);
}

# Required by Bio::Otter::Log::WithContextMixin
# (default version is not inside-out compatible!)
# FIXME: dup with B:O:L:DB

sub log_context {
    my ($self, $arg) = @_;

    if ($arg) {
        $log_context{$self} = $arg;
    }

    return $log_context{$self} if $log_context{$self};
    return '-B-V-Transform-Otter-Store unnamed-';
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::Otter::Store

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

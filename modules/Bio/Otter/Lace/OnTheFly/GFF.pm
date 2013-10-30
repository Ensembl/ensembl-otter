package Bio::Otter::Lace::OnTheFly::GFF;

use namespace::autoclean;

# Designed to mix in with Bio::Otter::Lace::OnTheFly::ResultSet
#
use Moose::Role;

with 'MooseX::Log::Log4perl';

use Bio::Otter::Utils::FeatureSort qw( feature_sort );
use Bio::Vega::Utils::EnsEMBL2GFF; # injection of to_gff() into EnsEMBL objects
use Bio::Vega::Utils::GFF;

requires 'analysis_name';
requires 'hit_by_query_id';
requires 'hit_query_ids';

sub gff {
    my ($self, $ensembl_slice) = @_;

    return unless ($self->hit_query_ids);

    my $gff_version = 2;        # FIXME!! is this correct? (see other uses, from DataSet)

    my %gff_args = (
        gff_format        => Bio::Vega::Utils::GFF::gff_format($gff_version),
#       gff_source        => $self->analysis_name,
        gff_source        => $self->gff_method_tag, # TEMP for testing
        use_ensembl_cigar => 1,
        );

    my $gff = Bio::Vega::Utils::GFF::gff_header($gff_version,
                                                $ensembl_slice->seq_region_name,
                                                $ensembl_slice->start,
                                                $ensembl_slice->end);

    foreach my $hname (sort $self->hit_query_ids) {

        foreach my $ga (sort {
                $a->target_start <=> $b->target_start
                ||
                $a->query_start  <=> $b->query_start
                        } @{ $self->hit_by_query_id($hname) }) {

            foreach my $fp ( feature_sort $ga->ensembl_features ) {
                $fp->slice($ensembl_slice);
                $gff .= $fp->to_gff(%gff_args);
            }

        }

    }

    return $gff;
}

# TEMP for testing
sub gff_method_tag {
    my ($self) = @_;
    return $self->analysis_name . '_gff';
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF

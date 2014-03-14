package Bio::Otter::Utils::GetScript::LocalDB;

# Helper extensions for SQLite EnsEMBL features

use strict;
use warnings;

use base 'Bio::Otter::Utils::GetScript';

use Bio::Vega::Enrich::SliceGetSplicedAlignFeatures;
use Bio::Vega::Utils::GFF;
use Bio::Vega::Utils::EnsEMBL2GFF;

# new() provided by parent

# NB GetScript::LocalDB is a singleton,
# hence these class members are simple variables.

my $getscript_vega_slice;

# In vega_slice and get_feature, there is overlap with MFetcher, but probably not enough to share code?

sub vega_slice {
    my ($self) = @_;
    return $getscript_vega_slice if $getscript_vega_slice;

    my (  $cs, $type, $start, $end, $csver      ) = $self->read_args(
        qw(cs   type   start   end   csver_orig ) );

    my $slice;
    $self->time_diff_for( 'vega_slice', sub {
        $slice = $self->local_db->vega_dba->get_SliceAdaptor()->fetch_by_region(
            $cs,
            $type,
            $start,
            $end,
            1,      # somehow strand parameter is needed
            $csver,
            );
                          });

    return $getscript_vega_slice = $slice;
}

sub get_features {
    my ($self) = @_;

    my (  $feature_kind, $analysis) = $self->read_args(
        qw(feature_kind   analysis));

    my $slice = $self->vega_slice;

    my $features;
    my $getter_method = "get_all_${feature_kind}s";
    $self->time_diff_for(
        'get features',
        sub {
            $features = $slice->$getter_method($analysis);
            my $n_features = scalar(@$features);
            $self->log_message("get features: got ${n_features}");
        }
        );

    return $features;
}

sub send_feature_gff {
    my ($self, $features) = @_;

    # FIXME: require_args
    my (  $gff_source,    $gff_version, $type, $start, $end) = $self->read_args(
        qw(gff_source      gff_version   type   start   end));

    my %gff_args = (
        gff_format        => Bio::Vega::Utils::GFF::gff_format($gff_version),
        gff_source        => $gff_source,
        );
    my $gff;

    $self->time_diff_for(
        'write GFF',
        sub {
            $gff = Bio::Vega::Utils::GFF::gff_header($gff_version, $type, $start, $end);
            foreach my $f (@$features) {
                $gff .= $f->to_gff(%gff_args);
            }
        });

    # update the SQLite db
    $self->update_local_db($gff_source, 'from_localdb');

    # Send data to zmap on STDOUT
    $self->time_diff_for(
        'sending data', sub {
            print STDOUT $gff;
        } );

    # zmap waits for STDOUT to be closed as an indication that all
    # data has been sent, so we close the handle now so that zmap
    # doesn't tell otterlace about the successful loading of the column
    # before we have the SQLite db updated and the cache file saved.
    close STDOUT or die "Error writing to STDOUT; $!";

    return;
}

# Primarily for the benefit of tests
sub DESTROY {
    undef $getscript_vega_slice;
    return;
}

1;

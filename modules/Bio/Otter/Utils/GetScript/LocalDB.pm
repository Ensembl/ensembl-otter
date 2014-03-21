package Bio::Otter::Utils::GetScript::LocalDB;

# Helper extensions for SQLite EnsEMBL features

use strict;
use warnings;

use base 'Bio::Otter::Utils::GetScript';

use Bio::Otter::Utils::SliceFeaturesGFF;

# new() provided by parent

# NB GetScript::LocalDB is a singleton,
# hence these class members are simple variables.

my $getscript_sfg;
my $getscript_atc;

sub _sfg {
    my ($self) = @_;
    return $getscript_sfg if $getscript_sfg;

    # FIXME: require_args
    my %opts;
    @opts{qw(cs name start end csver      feature_kind logic_name gff_source gff_version)} = $self->read_args(
          qw(cs type start end csver_orig feature_kind analysis   gff_source gff_version) );

    my $sfg = Bio::Otter::Utils::SliceFeaturesGFF->new(
        dba          => $self->local_db->vega_dba,
        %opts,
        );

    # Time pre-load of slice
    $self->time_diff_for('vega_slice', sub { return $sfg->slice } );

    return $getscript_sfg = $sfg;
}

sub vega_slice {
    my ($self) = @_;
    return $self->_sfg->slice;
}

sub get_features {
    my ($self) = @_;

    my $features;
    $self->time_diff_for('get features', sub { return $features = $self->_sfg->features_from_slice } );

    my $n_features = scalar(@$features);
    $self->log_message("get features: got ${n_features}");

    return $features;
}

sub _accession_type_cache {
    my ($self) = @_;
    return $getscript_atc if $getscript_atc;

    require Bio::Otter::Lace::AccessionTypeCache; # only if needed

    my $atc = Bio::Otter::Lace::AccessionTypeCache->new;
    $atc->DB($self->local_db);

    return $getscript_atc = $atc;
}

{
    my $hit_description_loaded;

    sub _build_HitDescription {
        my ($self, @args) = @_;

        unless ($hit_description_loaded) {
            require Bio::Vega::HitDescription; # only if needed
            $hit_description_loaded = 1;
        }

        return Bio::Vega::HitDescription->new(@args);
    }
}

sub augment_feature_info {
    my ($self, $features) = @_;

    my $atc = $self->_accession_type_cache;
    foreach my $feature (@$features) {
        my $info = $atc->feature_accession_info($feature->hseqname);
        if ($info) {
            my $hd = $self->_build_HitDescription(
                -hit_name            => $feature->hseqname,
                -hit_length          => $info->{length},
                -hit_sequence_string => $info->{sequence},
                -description         => $info->{description},
                -taxon_id            => $info->{taxon_id},
                -db_name             => $info->{source_db},
                );
            $feature->{'_hit_description'} = $hd;
        }
    }
    return $features;
}

sub send_feature_gff {
    my ($self, $features, $process_gff) = @_;

    # # Example of passing extra gff args:
    # #
    # $self->_sfg->extra_gff_args({
    #     use_cigar_exonerate => 1, # TEMP for testing
    #                             });

    my $gff;
    $self->time_diff_for('write GFF', sub { return $gff = $self->_sfg->gff_for_features($features) } );

    # update the SQLite db
    $self->update_local_db($self->arg('gff_source'), '-no-gff-cache-file-for-localdb-', $process_gff);

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
    undef $getscript_sfg;
    return;
}

1;

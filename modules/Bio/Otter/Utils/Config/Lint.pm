=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Utils::Config::Lint;
use strict;
use warnings;

use File::Slurp 'slurp';
use List::MoreUtils 'uniq';

use Bio::Otter::Lace::Defaults;
use Bio::Otter::Version;


=head1 NAME

Bio::Otter::Utils::Config::Lint - check an otter_config

=head1 SYNOPSIS

 use Bio::Otter::Utils::Config::Lint;
 my $lint = Bio::Otter::Utils::Config::Lint->new('otter_config');
 # the config should match the code by major version,
 # and this cannot be checked here
 my @bad = $lint->check;
 my $ok = !@bad;

=head1 DESCRIPTION

This code is called from F<team_tools/bin/server-config-op> for the
Git commit hook.

Since it currently relies on L<Bio::Otter::Lace::Defaults>'s class
variables, it destroys any existing loaded configuration - once on
instantiation and again on destruction.


=head1 WHAT IS CHECKED?

=head2 Column ordering, and clustered columns

The column ordering should name columns which exist and are not
components of a clustered column.  RT#436982.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut


sub new {
    my ($class, $filename) = @_;
    my $self = { fn => $filename };
    bless $self, $class;
    $self->_init;
    return $self;
}

sub _init {
    my ($self) = @_;
    my $fn = $self->{fn};
    my $cfg = slurp($fn);

    # Destroy existing loaded config,
    # when replacing it do not read (user_config_filename)
    Bio::Otter::Lace::Defaults::testmode_redirect_reset('/absent');

    local @ARGV = ();
    Bio::Otter::Lace::Defaults::do_getopt();
    Bio::Otter::Lace::Defaults::save_server_otter_config($cfg);

    return;
}

sub DESTROY {
    Bio::Otter::Lace::Defaults::testmode_redirect_reset();
    return;
}


sub check {
    my ($self) = @_;
    my @bad;

    my @sec = my ($uni, $di, $tri) =
      Bio::Otter::Lace::Defaults::config_sections();

    # uni = list
    #   qw( client RequestQueue Peer ) # no checks

    # di = list
    #   $species.bam_list
    #   $species.metakey_to_resource_bin
    #   (default|$species).use_filters
    #   (default|$species).controlled_vocabulary_(transcript|locus)
    #   default. qw( blixem zmap zmap_config ZMapWindow )

    # tri = hash(key1.key2 => [ key3, ... ])
    #   default.filter.*
    #   $species.filter.*
    #   $species.bam.*
    #
    # Some key3 values also contain '.' but it is a local separator
    # e.g. in sheep.filter
    #
    # As returned by
    #   my $key3 = Bio::Otter::Lace::Defaults::config_keys($species, 'filter');

    my @di_tri_key1 = map { (split /\./, $_)[0] } (@$di, keys %$tri);
    my @species = sort( grep { $_ ne 'default' } uniq(@di_tri_key1) );
    foreach my $species (@species) {
        my @key3 = uniq( @{ $tri->{"$species.filter"} },
                         @{ $tri->{'default.filter'} } );
        push @bad,
          map {"$species: $_"}
            $self->check_species($species, sort @key3);
    }

    push @bad, $self->check_species_configured(@species);

# my @cfg_fn = Bio::Otter::Lace::Defaults::config_filenames();
# use YAML 'Dump'; print Dump({ sec => \@sec, cfg_fn => \@cfg_fn, species => \@species });

    return @bad;
}


sub check_species {
    my ($self, $species, @comp_col) = @_;
    my @bad;

    # Columns which should be available to load
    my $used = # { column_name => selected_by_default }
      Bio::Otter::Lace::Defaults::config_section($species, 'use_filters');
    # $species.use_filters + default.use_filters

    # Find all columns and decide whether they are components to load
    # or clusters into which those components are grouped for display.
    #
    #   simple example of clustering is RepeatMasker and TRF, which
    #   are separate sources in Otter but both have
    #   zmap_column=Repeats and so appear in the same column in ZMap.
    #
    my %comp_col;    # { $comp_col => $clus_col }, value undef = not clustered
    my %cluster_col; # { $clus_col => comp_count }
    # where [$species.filter.$comp_col] zmap_column=$clus_col
    foreach my $comp_col (@comp_col) {
        my $clus = Bio::Otter::Lace::Defaults::config_value
          ("$species.filter.$comp_col", 'zmap_column');
        $clus = Bio::Otter::Lace::Defaults::config_value
          ("default.filter.$comp_col", 'zmap_column') if !defined $clus;
        # It's okay for a single column to have a self-named zmap_column
        # (e.g. curated_features)
        $clus = undef if ($clus and $comp_col eq $clus);

        $comp_col{$comp_col} = $clus;
        $cluster_col{$clus} ++ if defined $clus;
    }

    # Check partitioning on cluster/component
    my @loop_comp_is_clus = grep { $cluster_col{$_} } sort(keys %comp_col);
    push @bad, "Found component column (@loop_comp_is_clus) was target of [*.filter.*]zmap_column cluster"
      if @loop_comp_is_clus;

    my @loop_clus_in_clus =
      grep { defined $comp_col{$_} } sort(keys %cluster_col);
    push @bad, "Found clustered column (@loop_clus_in_clus) re-clustered with [*.filter.*]zmap_column"
      # this might be ok, but there are none just now
      if @loop_clus_in_clus;

    # Check for case collision - could be bad, since ZMap lower-cases
    # internally
    my %lc_all_col;
    foreach my $col (keys %comp_col, keys %cluster_col) {
        $lc_all_col{ lc($col) } ++;
    }
    my @lc_dup = grep { $lc_all_col{$_} > 1 } sort(keys %lc_all_col);
    push @bad, "Duplicate or case-collided column (@lc_dup)" if @lc_dup;

    # Reject clusters from use_filters
    #
    #   use_filters lists the actual source (eg. RAMPAGE_pks_filtered_temporal_lobe_minus).
    #   "zmap_column=RAMPAGE_filtered_minus" just tells ZMap where to
    #   show the data in the ZMap view - it has nothing to do with
    #   configuring the filter in Otter or fetching the data.
    my @clus_used = grep { $cluster_col{$_} } sort(keys %$used);
    push @bad, "Column-cluster name (@clus_used) given in *.use_filters"
      if @clus_used;

    my $order = Bio::Otter::Lace::Defaults::config_value_list_merged
      ($species, 'zmap_config', 'columns');
    # [$species.zmap_config] and [default.zmap_config] columns
    my %order;
    @order{@$order} = ();

    my @comp_in_order = grep { defined $comp_col{$_} } (sort @$order);
    my @comp_replace = uniq(map { $comp_col{$_} } @comp_in_order);
    my @comp_replace_ordered = grep { exists $order{$_} } @comp_replace;
    @comp_replace = grep { !exists $order{$_} } @comp_replace;
    push @bad, sprintf
      ("Component column%s (%s) found in [*.zmap_config]columns%s%s",
       (@comp_in_order == 1 ? '' : 's'), (join '|', @comp_in_order),
       (@comp_replace ? ", replace with (@comp_replace)" : ''),
       (@comp_replace_ordered
        ? ", note (@comp_replace_ordered) already present" : ''))
        if @comp_in_order;

#use YAML 'Dump';
#print Dump({ species => $species,
#             columns => { clustered => \%cluster_col, component => \%comp_col },
#             order => $order, use_filters => $used })
#if $species eq 'human';

    return @bad;
}


sub check_species_configured {
    my ($self, @cfg_species) = @_;
    # XXX: compare this against species listed in species.dat
    return ();
}

1;

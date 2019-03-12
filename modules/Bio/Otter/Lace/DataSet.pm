=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Lace::DataSet

package Bio::Otter::Lace::DataSet;

use strict;
use warnings;
use Carp;
use Scalar::Util 'weaken';
use URI::Escape qw( uri_escape );
use Try::Tiny;

use Bio::Otter::Debug;
use Bio::Otter::Source::Filter;
use Bio::Otter::Source::BAM;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub Client {
  my ($self, $client) = @_;
  if ($client) {
    $self->{'_Client'} = $client;
    weaken $self->{'_Client'};
  }
  $client = $self->{'_Client'};
  confess "No otter Client attached" unless $client;
  return $client;
}

sub load_client_config {
    my ($self) = @_;

    $self->_bam_load    unless $self->{_bam_by_name};
    $self->_filter_load unless $self->{_filter_by_name};
    return;
}

sub name {
    my ($self, $name) = @_;

    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub gff_version {
    my ($self) = @_;
    return $self->{'_gff_version'} ||=
        $self->Client->config_value('gff_version');
}

sub acedb_version {
    my ($self) = @_;
    return $self->{'_acedb_version'} ||=
        $self->Client->config_value('acedb_version');
}

sub zmap_config_global {
    my ($self) = @_;
    my $short_title = $self->Client->config_value('short_window_title_prefix');
    my $st = $short_title ? 'true' : 'false';
    my $xremote_debug = Bio::Otter::Debug->debug('XRemote');
    my $xrd = $xremote_debug ? 'true' : 'false';
    my $to_list = $self->Client->config_section_value(Peer => 'timeout-list');
    return <<"CONF";

[ZMap]
show-mainwindow = false
abbrev-window-title = $st
xremote-debug = $xrd

[logging]
show-time = true

[Peer]
timeout-list = $to_list
CONF
}

sub zmap_config {
    my ($self, $session) = @_;

    my $ds_name = $self->name;
    my $gff_version = $self->gff_version;
    my $import_argument_string =
        "--dataset=${ds_name} --gff_version=${gff_version}";

    my $stanza = { %{ $self->config_section('zmap') } };

    my $columns_list = $self->config_value_list_merged('zmap_config', 'columns');
    $stanza->{columns} = $columns_list if @${columns_list};

    my $config = {
        'ZMap' => $stanza,
        'ZMapWindow' => $self->config_section('ZMapWindow'),

        # BAM and bigWig imported via ZMap File menu
        'columns' => {
            'Short Read Data' => [qw{ BAM bigWig }],
        },
        'featureset-style' => {
            'BAM'    => 'short-read',
            'bigWig' => 'short-read-coverage',
        },
        'import' => {
            'gff_get'       => [ 'GFF',    $import_argument_string ],
            'bam_get'       => [ 'BAM',    $import_argument_string ],
            'bigwig_get'    => [ 'bigWig', $import_argument_string ],
        },

    };

    $self->_add_zmap_source_config($config, $session);
    $self->_add_zmap_bam_config($config, $session);

    return $config;
}

sub _add_zmap_source_config {
    my ($self, $config, $session) = @_;

    my $sources = $self->sources;

    $self->_add_zmap_source_config_one($config, $session, $_) for @{$sources};

    $config->{'ZMap'}{'sources'} =
        [ sort @{$config->{'ZMap'}{'sources'}} ]
        if @{$sources};

    return;
}

sub _add_zmap_source_config_one {
    my ($self, $config, $session, $source) = @_;

    my $name = $source->name;

    push @{$config->{'ZMap'}{'sources'}}, $name;
    push @{$config->{'ZMap'}{'seq-data'}}, $name if $source->is_seq_data;

    $config->{$name} = {
        url         => $source->url($session),
        featuresets => $source->featuresets,
        delayed     => 'true',
        stylesfile  => $session->stylesfile,
        group       => 'always',
    };

    if (my $zmap_column = $source->zmap_column) {
        push @{$config->{'columns'}{$zmap_column}}, @{$source->featuresets};
    }

    if (my $zmap_style = $source->zmap_style) {
        $config->{'featureset-style'}{$name} = $zmap_style;
    }

    if (my $description = $source->description) {
        $config->{'featureset-description'}->{$name} = $description;
    }

    return;
}

sub _add_zmap_bam_config {
    my ($self, $config, $session) = @_;

    # This handles special configuration parameters that are specific
    # to BAM sources, such as those relating to sequence and coverage
    # data.  The normal configuration stanzas for BAM sources are
    # already handled by _add_zmap_source_config().

    my $stylesfile = $session->stylesfile;
    my $slice      = $session->slice;

    # must be careful here because different BAM objects may have the
    # same parent_column or parent_featureset

    my $column_featureset_hash = { };

    for my $bam ( @{$self->bam_list} ) {
        my $bam_column = $bam->name;

        # coverage columns and featuresets
        my $coverage_column = $bam->parent_column;
        my $coverage_featureset = $bam->parent_featureset;
        next unless $coverage_column && $coverage_featureset;
        $column_featureset_hash->{$coverage_column}{$coverage_featureset}++;

        # related columns
        my $related_column = "${coverage_featureset}_reads";
        my $related_featureset = $bam->name;
        $column_featureset_hash->{$related_column}{$related_featureset}++;

        for (
            [ "${bam_column}_coverage_plus",  $bam->coverage_plus,   1 ],
            [ "${bam_column}_coverage_minus", $bam->coverage_minus, -1 ],
            ) {
            my ( $featureset, $file, $strand ) = @{$_};
            next unless $file;
            push @{$config->{ZMap}{sources}}, $featureset;
            push @{$config->{featuresets}{$coverage_featureset}}, $featureset;
            $config->{'featureset-style'}{$coverage_featureset} = 'short-read-coverage';
            $config->{'featureset-related'}{$coverage_featureset} = $related_column;
            $config->{'featureset-style'}{$featureset} = 'short-read-coverage';
            $config->{'featureset-related'}{$featureset} = $related_column;
            my $query = {
                dataset => $self->name,
                chr   => $slice->ssname,
                start => $slice->start,
                end   => $slice->end,
                csver_remote => $bam->csver,
                file   => $file,
                strand => $strand,
                gff_source  => $featureset,
                gff_version => $self->gff_version,
            };
            my $query_string = _query_string($query);
            my $url = sprintf "pipe:///%s?%s", 'bigwig_get', $query_string;
            $config->{$featureset} = {
                featuresets => $featureset,
                delayed     => 'true',
                group       => 'always',
                stylesfile  => $stylesfile,
                url         => $url,
            };
        }
    }

    # add the columns to the ZMap configuration
    my @columns = sort keys %{$column_featureset_hash};
    push @{$config->{ZMap}{columns}}, sort @columns;
    $config->{columns}{$_} =
        [ sort keys %{$column_featureset_hash->{$_}} ]
        for @columns;

    return;
}

sub _query_string {
    my ($query) = @_;
    my $arguments = [ ];
    for my $key (sort keys %{$query}) {
        my $value = $query->{$key};
        next unless defined $value;
        push @{$arguments}, sprintf '-%s=%s', $key, uri_escape($value);
    }
    my $query_string = join '&', @{$arguments};
    return $query_string;
}

sub blixem_config {
    my ($self) = @_;


    my $config = {};
    $self->generate_blixem_bam_config($config);
    $self->generate_blixem_data_type_config($config);
    return $config;
}

sub generate_blixem_bam_config {
    my ($self, $config) = @_;

    $config->{'short-read'} = {
        'link-features-by-name'     => 'false',
        'bulk-fetch'                => 'bam-fetch',
        'user-fetch'                => 'none',
        'squash-linked-features'    => 'false',
        'squash-identical-features' => 'true',
    };

    my $fetch_arg_list = join ' ', qw(
        --gff_version=%g
        --gff_source=%S
        --dataset=%(dataset)
        --csver=%(csver)
        --chr=%r --start=%s --end=%e
        --file=%(file)
        );

    $config->{'bam-fetch'} = {
        'fetch-mode'    => 'command',
        'command'       => 'bam_get',
        'args'          => $fetch_arg_list,
        'output'        => 'gff',
    };

    foreach my $bam (@{$self->bam_list}) {
        $config->{$bam->name} = {
            'description'   => $bam->description,
            'file'          => $bam->file,
            'csver'         => $bam->csver,
            'dataset'       => $self->name,
        };
    }

    return;
}

sub generate_blixem_data_type_config {
    my ($self, $config) = @_;

    my $dt_config = $config->{'source-data-types'} = {};
    foreach my $filter (@{$self->filters}) {
        if (my $blx_dt = $filter->blixem_data_type) {
            foreach my $fs (@{$filter->featuresets}) {
                $dt_config->{$fs} = $blx_dt;
            }
        }
    }

    return;
}

sub _bam_load {
    my ($self) = @_;

    my $bam_by_name = $self->{_bam_by_name} = { };
    for my $name ( @{$self->config_keys("bam")} ) {
        my $config = $self->config_section("bam.${name}");
        try {
            my $bam = Bio::Otter::Source::BAM->new($name, $config);
            $bam->wanted(0);
            $bam->init_resource_bin;
            $bam_by_name->{$name} = $bam;
        }
        catch { warn sprintf "BAM section for ${name}: ignored: $_"; };
    }

    my $config = $self->config_section('bam_list');
    my @name_list = grep { $config->{$_} } keys %{$config};
    my $bam_list = $self->{_bam_list} =
        [ grep { defined } @{$bam_by_name}{@name_list} ];

    return;
}

sub bam_by_name {
    my ($self, $name) = @_;
    return $self->{_bam_by_name}{$name};
}

sub bam_list {
    my ($self) = @_;
    return $self->{_bam_list};
}

sub _filter_load {
    my ($self) = @_;

    my $filter_by_name = $self->{_filter_by_name} = { };
    my $mk_to_rb_config = $self->config_section('metakey_to_resource_bin');

    for my $name ( @{$self->config_keys("filter")} ) {
        my $config = $self->config_section("filter.${name}");
        try {
            my $filter= Bio::Otter::Source::Filter->from_config($config);
            $filter->name($name);
            $filter->init_resource_bin($mk_to_rb_config);
            $filter_by_name->{$name} = $filter;
        }
        catch { warn sprintf "filter section for ${name}: ignored: $_"; };
    }

    my $filters = $self->{_filters} = [ ];
    my $config = $self->config_section("use_filters");
    $self->_filter_add($_, $config->{$_}) for keys %{$config};

    return;
}

sub _filter_add {
    my ($self, $name, $wanted) = @_;
    my $filter = $self->{_filter_by_name}{$name};
    # Uncomment for debugging:
    # warn sprintf "_filter_add: '%s', wanted=%s, found=%s\n", $name, $wanted ? 1 : 0, $filter ? 'yes' : 'no';
    return unless $filter;
    my $remove;
    if ($wanted and $wanted eq 'REMOVE') {
        $remove = 1;
        $wanted = 0;
    }
    $filter->wanted($wanted);
    push @{$self->{_filters}}, $filter unless $remove;
    return;
}

sub add_filter {
    my ($self, $filter) = @_;
    my $name = $filter->name;
    $self->{_filter_by_name}->{$name} = $filter;
    $self->_filter_add($name, 1);
    return;
}

sub filter_by_name {
    my ($self, $name) = @_;
    return $self->{'_filter_by_name'}{$name};
}

sub filters {
    my ($self) = @_;
    return $self->{_filters};
}

sub sources {
    my ($self) = @_;
    return $self->{_sources} ||= [
        @{$self->filters},
        @{$self->bam_list},
        ];
}

sub config_section {
    my ($self, $section) = @_;
    return $self->Client->config_section($self->config_name, $section);
}

sub config_keys {
    my ($self, $key) = @_;
    return $self->Client->config_keys($self->config_name, $key);
}

sub config_value_list {
    my ($self, @keys) = @_;
    return $self->Client->config_value_list($self->config_name, @keys);
}

sub config_value_list_merged {
    my ($self, @keys) = @_;
    return $self->Client->config_value_list_merged($self->config_name, @keys);
}

sub config_name {
    my ($self) = @_;
    my $name = $self->ALIAS || $self->name;
    return $name;
}

sub meta_hash {
    my ($self) = @_;
    # Get all of meta table in one call
    return $self->{'_meta_hash'} ||=
        $self->Client->get_meta($self->name);
}

sub get_meta_value {
    my ($self, $key) = @_;

    my $values = $self->meta_hash->{values}->{$key};

    confess "No entry in meta table under key '$key'" if ! @{$values};
    confess "Multiple entries in meta table under key '$key'" if @{$values} > 1;

    return $values->[0];
}

sub db_info_hash {
    my ($self) = @_;
    # Get all db_info in one call
    return $self->{'_db_info_hash'} ||=
        $self->Client->get_db_info($self->name);
}

sub get_db_info_item {
    my ($self, $key) = @_;

    my $item = $self->db_info_hash->{$key};
    confess "No entry in db_info under key '$key'" unless $item;

    return $item;
}

sub vocab_locus {
    my ($self) = @_;
    return $self->{'_vocab_locus'} ||=
        $self->config_section('controlled_vocabulary_locus');
}

sub vocab_transcript {
    my ($self) = @_;
    return $self->{'_vocab_transcript'} ||=
        $self->config_section('controlled_vocabulary_transcript');
}

sub taxon {
    my ($self) = @_;

    unless ($self->{'_taxon_id'}) {
        $self->{'_taxon_id'} = $self->get_meta_value('species.taxonomy_id');
    }
    return $self->{'_taxon_id'};
}

sub species {
    my ($self) = @_;

    unless ($self->{'_species'}) {
        $self->{'_species'} = $self->get_meta_value('species.common_name');
    }
    return $self->{'_species'};
}

sub stable_id_prefix {
    my ($self) = @_;

    unless ($self->{'_stable_id_prefix'}) {
        my $pri = $self->get_meta_value('prefix.primary');
        my $spe = $self->get_meta_value('prefix.species');
        confess
"Need entries for both 'prefix.primary' and 'prefix.species' in otter meta table"
          unless $pri and $spe;
        $self->{'_stable_id_prefix'} = "$pri$spe";
    }
    return $self->{'_stable_id_prefix'};
}

sub sequence_sets_cached {
  my ($self, $ss) = @_;
  if ($ss) {
    $self->{'_sequence_sets'} = $ss;
  }
  return $self->{'_sequence_sets'};
}

sub get_all_visible_SequenceSets {
  my ($self) = @_;
  my $ss_list= $self->get_all_SequenceSets();
  my $visible = [];
  foreach my $ss (@$ss_list) {
     unless($ss->is_hidden) {
        push @$visible, $ss;
     }
  }
  return $visible;
}

sub get_all_SequenceSets {
  my ($self) = @_;
  my $seq_sets =$self->sequence_sets_cached;
  return $seq_sets if (defined($seq_sets) && scalar(@$seq_sets));

  my $client = $self->Client;
  $seq_sets = $client->get_all_SequenceSets_for_DataSet($self);
  $self->sequence_sets_cached($seq_sets);

  return $seq_sets;
}

sub get_SequenceSet_by_name {
    my ($self, $name) = @_;
    confess "missing name argument" unless $name;
    my $ss_list = $self->get_all_SequenceSets;
    foreach my $ss (@$ss_list) {
        if ($name eq $ss->name) {
            return $ss;
        }
    }
    confess "No SequenceSet called '$name'";
}

sub selected_SequenceSet {
    my ($self, $selected_SequenceSet) = @_;
    if ($selected_SequenceSet) {
        $self->{'_selected_SequenceSet'} = $selected_SequenceSet;
    }
    return $self->{'_selected_SequenceSet'};
}

sub fetch_all_CloneSequences_for_selected_SequenceSet { # without any lock info
    my ($self) = @_;

    my $ss = $self->selected_SequenceSet
        or confess "No SequenceSet is selected";
    return $self->fetch_all_CloneSequences_for_SequenceSet($ss);
}

sub fetch_all_CloneSequences_for_SequenceSet { # without any lock info
    my ($self, $ss) = @_;
    confess "Missing SequenceSet argument" unless $ss;
    my $client = $self->Client;
    my $cs_list=$client->get_all_CloneSequences_for_DataSet_SequenceSet($self, $ss);
    return $cs_list;
}

sub fetch_notes_locks_status_for_SequenceSet {
    my ($self, $ss) = @_;
    confess "Missing SequenceSet argument" unless $ss;
    my $client = $self->Client;

    $client->fetch_all_SequenceNotes_for_DataSet_SequenceSet($self, $ss);
    $client->lock_refresh_for_DataSet_SequenceSet($self, $ss);
    $client->status_refresh_for_DataSet_SequenceSet($self, $ss);

    return;
}

sub zmap_arg_list {
    my ($self, $ss) = @_;
    my $arg_list =
        $self->config_value_list('zmap_config', 'arguments');
    return $arg_list;
}


### DBI info indirects through Bio::Otter::SpeciesDat::Database
#
#   Database passwords are no longer passed from Otter Server,
#   this is backwards compatibility for old scripts.
#
#   This new code needs species.dat be229b40

sub DBSPEC {
    my ($self, $DBSPEC) = @_;

    if(defined($DBSPEC)) {
        $self->{'_DBSPEC'} = $DBSPEC;
    }
    return $self->{'_DBSPEC'};
}

sub DNA_DBSPEC {
    my ($self, $DNA_DBSPEC) = @_;

    if(defined($DNA_DBSPEC)) {
        $self->{'_DNA_DBSPEC'} = $DNA_DBSPEC;
    }
    return $self->{'_DNA_DBSPEC'};
}

my $_bwarp; # one noise is enough
sub _dbspec {
    my ($self) = @_;
    carp 'DBI access via B:O:Lace:DS is deprecated (and slow)' unless $_bwarp++;
    my $dbspec = $self->DBSPEC
      or croak "$self didn't get DBSPEC from species.dat";
    require Bio::Otter::Server::Config;
    return Bio::Otter::Server::Config->Database($dbspec);
}

sub _dna_dbspec {
    my ($self) = @_;
    carp 'DBI access via B:O:Lace:DS is deprecated (and slow)' unless $_bwarp++;
    my $dna_dbspec = $self->DNA_DBSPEC
      or croak "$self didn't get DNA_DBSPEC from species.dat";
    require Bio::Otter::Server::Config;
    return Bio::Otter::Server::Config->Database($dna_dbspec);
}

#
# DB connection handling
#-------------------------------------------------------------------------------
#
sub get_cached_DBAdaptor {
    my ($self) = @_;

    unless($self->{'_dba_cache'}){
        my $tmp = $self->make_Vega_DBAdaptor;
        $self->_attach_DNA_DBAdaptor($tmp) if $self->DNA_DBNAME;
        $self->{'_dba_cache'} = $tmp;
    }
    #warn "OTTER DBADAPTOR = '$dba'";
    return $self->{'_dba_cache'};
}

sub make_EnsEMBL_DBAdaptor {
    my ($self) = @_;

    require Bio::EnsEMBL::DBSQL::DBAdaptor;
    return $self->_make_DBAdaptor_with_class('Bio::EnsEMBL::DBSQL::DBAdaptor');
}

sub make_Vega_DBAdaptor {
    my ($self) = @_;

    require Bio::Vega::DBSQL::DBAdaptor;
    return $self->_make_DBAdaptor_with_class('Bio::Vega::DBSQL::DBAdaptor');
}

sub get_pipeline_DBAdaptor {
    my ($self, $writable) = @_;
    my $o_dba = $self->get_cached_DBAdaptor;

    # runtime, because most clients don't need it
    require Bio::Otter::Lace::PipelineDB;

    if ($writable) {
        return Bio::Otter::Lace::PipelineDB::get_pipeline_rw_DBAdaptor($o_dba);
    } else {
        return Bio::Otter::Lace::PipelineDB::get_pipeline_DBAdaptor($o_dba);
    }
}

sub _make_DBAdaptor_with_class {
    my ($self, $class) = @_;

    my (@args) = (
        # Extra arguments to stop Bio::EnsEMBL::Registry issuing warnings
        -GROUP      => "otter:$class",
        -SPECIES    => $self->name,
        );

    foreach my $prop ($self->list_all_db_properties) {
        if (my $val = $self->$prop()) {
            push(@args, "-$prop", $val);
        }
    }
    warn "About to $class->new(@args) without -USER.  No databases.yaml ?"
      unless grep { $_ eq '-USER' } @args;

    return $class->new(@args);
}
sub _attach_DNA_DBAdaptor{
    my ($self, $dba) = @_;

    die "Nothing to attach to?" unless $dba;

    my (@ott_args, @dna_args);
    foreach my $this ($self->list_all_db_properties) {
        if (my ($prop) = $this =~ /^DNA_(\w+)/) {
            if (my $val = $self->$this()) {
                push(@dna_args, "-$prop", $val);
                push(@ott_args, "-$prop", $self->$prop());
            }
        }
    }

    if(("@dna_args" eq "@ott_args") && @dna_args){
        die "They are the same the DBAdaptor will just return itself\n";
    }elsif(@dna_args){
        #warn "dna_args: @dna_args\n";
        my $class = 'Bio::EnsEMBL::DBSQL::DBAdaptor';
        warn "About to $class->new(@dna_args) without -USER, for dnadb"
          unless grep { $_ eq '-USER' } @dna_args;
        my $dnadb = $class->new
          (@dna_args,
           # Extra arguments to stop Bio::EnsEMBL::Registry issuing warnings
           -GROUP      => 'dnadb',
           -SPECIES    => $self->name);
        $dba->dnadb($dnadb);
    }else{
        die "No DNA_* options found. *** CHECK species.dat ***\n";
    }

    return;
}

sub list_all_db_properties {
    # qw( DBSPEC DNA_DBSPEC ) are not listed because they aren't
    # passed to DBAdaptor
    return qw{
        HOST
        USER
        DNA_PASS
        PASS
        DBNAME
        DNA_PORT
        DNA_HOST
        DNA_USER
        DNA_DBNAME
        PORT
        ALIAS
        READONLY
        };
}

sub HOST {
    my ($self, $HOST) = @_;

    if(defined($HOST)) {
        carp 'Write now ignored';
        return;
    } else {
        return $self->_dbspec->host;
    }
}

sub USER {
    my ($self, $USER) = @_;
    if(defined($USER)) {
        carp 'Write now ignored';
        return;
    } else {
        return $self->_dbspec->user;
    }
}

sub DNA_PASS {
    my ($self, $DNA_PASS) = @_;
    if(defined($DNA_PASS)) {
        carp 'Write now ignored';
        return;
    } else {
        return $self->_dna_dbspec->pass;
    }
}

sub PASS {
    my ($self, $PASS) = @_;
    if(defined($PASS)) {
        carp 'Write now ignored';
        return;
    } else {
        return $self->_dbspec->pass;
    }
}

sub DBNAME {
    my ($self, $DBNAME) = @_;

    if(defined($DBNAME)) {
        $self->{'_DBNAME'} = $DBNAME;
    }
    return $self->{'_DBNAME'};
}

sub DNA_PORT {
    my ($self, $DNA_PORT) = @_;
    if(defined($DNA_PORT)) {
        carp 'Write now ignored';
        return;
    } else {
        return $self->_dna_dbspec->port;
    }
}

sub DNA_HOST {
    my ($self, $DNA_HOST) = @_;
    if(defined($DNA_HOST)) {
        carp 'Write now ignored';
        return;
    } else {
        return $self->_dna_dbspec->host;
    }
}

sub DNA_USER {
    my ($self, $DNA_USER) = @_;
    if(defined($DNA_USER)) {
        carp 'Write now ignored';
        return;
    } else {
        return $self->_dna_dbspec->user;
    }
}

sub DNA_DBNAME {
    my ($self, $DNA_DBNAME) = @_;

    if(defined($DNA_DBNAME)) {
        $self->{'_DNA_DBNAME'} = $DNA_DBNAME;
    }
    return $self->{'_DNA_DBNAME'};
}

sub PORT {
    my ($self, $PORT) = @_;
    if(defined($PORT)) {
        carp 'Write now ignored';
        return;
    } else {
        return $self->_dbspec->port;
    }
}

sub ALIAS {
    my ($self, $ALIAS) = @_;

    if(defined($ALIAS)) {
        $self->{'_ALIAS'} = $ALIAS;
    }
    return $self->{'_ALIAS'};
}

sub READONLY {
    my ($self, $READONLY) = @_;
    if(defined($READONLY)) {
        $self->{'_READONLY'} = $READONLY;
    }
    return $self->{'_READONLY'};
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::DataSet

=head1 DESCRIPTION

The B<Bio::Otter::Lace> objects are designed for
use with the annotators' B<otterlace> interface,
where simple data objects for use behind the
graphical interface of the long-running client
are needed.  The standard Ensembl DBAdaptor
scheme was not used so that the database handle
can be dropped.  (Because of the DBAdaptor system
design, the database connection is usually only
dropped when all the data objects go out of
scope.)

There are also objects to represent the extra
tables found in the B<lace.sql> file in the otter
distribution (such as sequence sets and notes).

=head2 DataSet - client side

The L<Bio::Otter::Lace::DataSet> object represents an entry in the
B<species.dat> file, which is, usually, a species
served by the otter server.

The DataSet object has an Ensembl B<DBAdaptor> -
it is the only object in the Lace system that
does.  It contains methods for saving data
to the extra tables defined in B<lace.sql>, and
which are represented by the other Lace data
objects.

Each DataSet contains one or more
B<SequenceSet>s.

=head2 DataSet - server side

See also L<Bio::Otter::SpeciesDat::DataSet>, which is normally (as of
v63) instantiated server-side.

It can be reached via L<Bio::Otter::Server::Config/SpeciesDat>.

=head2 SequenceSet

A SequenceSet is any list of clones that
annotators are working on, most often a
contiguous region of a genome.  Each SequenceSet
has a list of B<CloneSequence> objects.

=head2 CloneSequence

A CloneSequence is a container for some of the
data found in the Ensembl B<Clone> and B<Contig>
objects and in the B<assembly> table.  It has
zero or more B<SequenceNotes>, and, if there are
any, one of them is designated the current (most
recent) SeqeuenceNote.

=head2 SequenceNote

This is a remark added by an annotator to the
annotation interface to aid tracking the progress
of annotation.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


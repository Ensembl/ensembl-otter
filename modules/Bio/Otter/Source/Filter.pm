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


### Bio::Otter::Source::Filter

package Bio::Otter::Source::Filter;

use strict;
use warnings;

use Carp;
use URI::Escape qw( uri_escape );

use base 'Bio::Otter::Source';

my @server_params = (

    # session
    qw(
    server_script
    ),

    # common
    qw(
    analysis
    feature_kind
    metakey
    filter_module
    swap_strands
    url_string
    gff_source
    gff_feature
    ),
    [ qw( csver csver_remote ) ],
    ,

    # Ditag
    qw(
    ditypes
    ),

    # DAS
    qw(
    grouplabel
    dsn
    type_id
    source
    ),

    # PSL via SQL
    qw(
    db_dsn
    db_user
    db_pass
    db_table
    chr_prefix
    ),

    # Gene
    qw(
    transcript_analyses
    ),

    # Alignment
    qw(
    sequence_db
    zmap_style_root
    max_e_value
    ),

    # file_get
    qw(
    file_path
    ),

    # FuncGen
    qw(
    feature_set
    feature_type
    ),

    # bigwig
    qw(
    file
    strand
    ),

    );

sub from_config {
    my ($pkg, $config) = @_;

    die sprintf "no filter configuration" unless keys %{$config};

    die "you can't specify a zmap_style and multiple featuresets"
        if 1
        # NB: use redundant ( ... ) to discipline emacs mode indentation
        && ($config->{zmap_style})
        && ($config->{featuresets})
        && ($config->{featuresets} =~ /[,;]/)
        ;

    my $filter = $pkg->new;

    for my $key (keys %{$config}) {
        die "unrecognized configuration key '$key'"
            unless $filter->can($key);
        die "bad configuration key '$key'"
            unless $key =~ m{^[_a-zA-Z][_a-zA-Z0-9]{1,63}$};
        $filter->$key($config->{$key});
    }

    return $filter;
}

sub new {
    my ($obj_or_class, @args) = @_;

    confess "new() does not permit arguments" if @args;

    return bless {}, ref($obj_or_class) || $obj_or_class;
}

sub server_script {
    my ($self, $server_script) = @_;
    $self->{_server_script} = $server_script if defined $server_script;
    return $self->{_server_script};
}

sub url_string {
    my ($self, $url_string) = @_;

    if($url_string) {
        $self->{_url_string} = $url_string;
    }
    return $self->{_url_string};
}

sub analysis_name {
    my ($self, @args) = @_;
    return $self->analysis(@args);
}

sub analysis {
    my ($self, $analysis) = @_;

    if($analysis) {
        $self->{_analysis} = $analysis;
    }

    # the analysis name defaults to the filter name

    return $self->{_analysis} || $self->name;
}

sub metakey {
    my ($self, $metakey) = @_;

    if($metakey) {
        $self->{_metakey} = $metakey;
    }
    return $self->{_metakey};
}

sub feature_kind {
    my ($self, $feature_kind) = @_;
    $self->{_feature_kind} = $feature_kind if $feature_kind;
    return $self->{_feature_kind};
}

sub filter_module {
    my ($self, $filter_module) = @_;
    $self->{_filter_module} = $filter_module if $filter_module;
    return $self->{_filter_module};
}

sub swap_strands {
    my ($self, $swap_strands) = @_;
    $self->{_swap_strands} = $swap_strands if defined $swap_strands;
    return $self->{_swap_strands};
}

sub featuresets {
    my ($self, $featuresets) = @_;

    if ($featuresets) {
        $self->{_featuresets} =
            ref $featuresets ? $featuresets : [split(/\s*[,;]\s*/, $featuresets)];
    }

    # the list of featuresets defaults to the name of this filter
    return $self->{_featuresets} || [ $self->name ];
}

sub blixem_data_type {
    my ($self, $blixem_data_type) = @_;

    if ($blixem_data_type) {
        $self->{'_blixem_data_type'} = $blixem_data_type;
    }
    return $self->{'_blixem_data_type'};
}

sub ditypes {
    my ($self, $ditypes) = @_;

    if ($ditypes) {
        $self->{'_ditypes'} = $ditypes;
    }
    return $self->{'_ditypes'};
}

sub grouplabel {
    my ($self, $grouplabel) = @_;
    $self->{_grouplabel} = $grouplabel if $grouplabel;
    return $self->{_grouplabel};
}

sub dsn {
    my ($self, $dsn) = @_;
    $self->{_dsn} = $dsn if $dsn;
    return $self->{_dsn};
}

sub type_id {
    my ($self, $type_id) = @_;
    $self->{_type_id} = $type_id if $type_id;
    return $self->{_type_id};
}

sub source {
    my ($self, $source) = @_;
    $self->{_source} = $source if $source;
    return $self->{_source};
}

sub db_dsn {
    my ($self, $db_dsn) = @_;
    $self->{_db_dsn} = $db_dsn if $db_dsn;
    return $self->{_db_dsn};
}

sub db_user {
    my ($self, $db_user) = @_;
    $self->{_db_user} = $db_user if $db_user;
    return $self->{_db_user};
}

sub db_pass {
    my ($self, $db_pass) = @_;
    $self->{_db_pass} = $db_pass if $db_pass;
    return $self->{_db_pass};
}

sub db_table {
    my ($self, $db_table) = @_;
    $self->{_db_table} = $db_table if $db_table;
    return $self->{_db_table};
}

sub chr_prefix {
    my ($self, $chr_prefix) = @_;
    $self->{_chr_prefix} = $chr_prefix if $chr_prefix;
    return $self->{_chr_prefix};
}

sub transcript_analyses {
    my ($self, $transcript_analyses) = @_;
    $self->{_transcript_analyses} = $transcript_analyses if $transcript_analyses;
    return $self->{_transcript_analyses};
}

sub sequence_db {
    my ($self, $sequence_db) = @_;
    $self->{_sequence_db} = $sequence_db if $sequence_db;
    return $self->{_sequence_db};
}

sub zmap_style_root {
    my ($self, $zmap_style_root) = @_;
    $self->{_zmap_style_root} = $zmap_style_root if $zmap_style_root;
    return $self->{_zmap_style_root};
}

sub max_e_value {
    my($self, $flag) = @_;
    
    if (defined $flag) {
        $self->{'_max_e_value'} = $flag;
    }
    return $self->{'_max_e_value'};
}

sub file_path {
    my ($self, $file_path) = @_;
    $self->{_file_path} = $file_path if $file_path;
    return $self->{_file_path};
}

sub feature_set {
    my ($self, $feature_set) = @_;
    $self->{_feature_set} = $feature_set if $feature_set;
    return $self->{_feature_set};
}

sub feature_type {
    my ($self, $feature_type) = @_;
    $self->{_feature_type} = $feature_type if $feature_type;
    return $self->{_feature_type};
}

# session handling

sub _url_query_string { ## no critic(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $session) = @_;
    return join '&', @{$self->script_arguments($session)};
}

sub call_with_session_data_handle {
    my ($self, $session, $data_sub) = @_;

    my $script = $self->script_name;
    my @command = ( $script, @{$self->script_arguments($session)} );

    open my $data_h, '-|', @command
        or confess "failed to run $script: $!";

    $data_sub->($data_h);

    close $data_h
        or confess $!
        ? "error closing $script: $!"
        : "$script failed: status = $?";

    return;
}

sub script_arguments {
    my ($self, $session) = @_;

    my $params = {
        %{ $session->script_arguments },
        ( map { $self->_param_value($_) } @server_params ),
    };
    $params->{gff_seqname} = $params->{'chr'};

    my $arguments = [ ];
    for my $key (sort keys %{$params}) {
        my $value = $params->{$key};
        next unless defined $value;
        push @$arguments, join "=", uri_escape($key), uri_escape($value);
    }

    return $arguments;
}

sub gff_feature {
    my ($self, $feature) = @_;

    if ($feature) {
        $self->{'_gff_feature'} = $feature;
    }
    return $self->{'_gff_feature'};
}

sub strand {
    my ($self, $feature) = @_;

    if ($feature) {
        $self->{'_strand'} = $feature;
    }
    return $self->{'_strand'};
}

sub script_name {
    my ($self, $script) = @_;

    if ($script) {
        $self->{'_script_name'} = $script;
    }
    return $self->{'_script_name'} || "filter_get"; # see also Bio::Otter::Utils::About
}

sub is_seq_data {
    my ($self, $flag) = @_;

    if (defined $flag) {
        $self->{'_is_seq_data'} = $flag;
    }
    return $self->{'_is_seq_data'};
}

sub init_resource_bin {
    my ($self, $mk_to_rb_config) = @_;

    my $resource_bin = $self->resource_bin;

  SWITCH: {
      $resource_bin                                and return $resource_bin; # already explicitly set

      if ($self->source) {
          $resource_bin = $self->resource_bin_from_uri($self->source);
          last SWITCH;
      }

      my $metakey   = $self->metakey || 'pipeline_db_head';                  # default is for core columns

      $resource_bin = $mk_to_rb_config->{$metakey} and last SWITCH;          # we know the resource for the metakey
      $resource_bin = $metakey;                        last SWITCH;          # fallback to metakey itself
    }

    # warn "setting '", $self->name, "' resource_bin to: '", $resource_bin, "'\n";
    return $self->resource_bin($resource_bin);
}

1;

__END__

=head1 NAME - Bio::Otter::Source::Filter

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


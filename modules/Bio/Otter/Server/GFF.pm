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


package Bio::Otter::Server::GFF;

use strict;
use warnings;

use Bio::Otter::Utils::AccessionInfo::Serialise qw( fasta_header_column_order escape_fasta_description );
use Bio::Otter::Utils::RequireModule qw(require_module);
use Bio::Vega::Enrich::SliceGetAllAlignFeatures;
use Bio::Vega::Enrich::SliceGetSplicedAlignFeatures;
use Bio::Vega::Utils::Detaint qw( detaint_sprintfn_url_fmt );
use Bio::Vega::Utils::GFF;
use Bio::Vega::Utils::EnsEMBL2GFF;

use base qw( Bio::Otter::Server::Support::Web );

my @gff_keys = qw(
    gff_feature
    gff_source
    gff_seqname
    url_string
    author
    );

my $SUBCLASS = {
    features         => '',          # no subclass

    das_features     => 'DAS',
    funcgen_features => 'FuncGen',
    genes            => 'Genes',
    grc_issues       => 'GRCIssues',
    patch_features   => 'Patches',
    psl_sql_features => 'PslSql',
};

sub send_requested_features {
    my ($pkg) = @_;
    
    my $specific_pkg = $pkg;
    
    if (my $path_info = $pkg->path_info) {

        my ($key) = $path_info =~ m{^/(\w+)$};
        die "Subclass key not found in '$path_info'\n" unless $key;

        my $subclass = $SUBCLASS->{$key};
        die "Subclass for '$key' not known\n" unless defined $subclass;

        $specific_pkg = join '::', __PACKAGE__, $subclass if $subclass;
        require_module($specific_pkg);
    }

    return $specific_pkg->do_send_features;
}

sub do_send_features {
    my ($pkg) = @_;

    $pkg->send_response(
        -compression => 1,
        sub {
            my ($self) = @_;
            my $features = $self->get_requested_features;

            my $fasta_gff = '';
            my $accession_info;
            if (my $seq_db_list = $self->sequence_database_list) {
                my %hseq;
                foreach my $feat (@$features) {
                    # Here we assume that all features where a sequence_db list
                    # is provided will have the hseqname method.
                    $hseq{$feat->hseqname} = 1;
                }
                if (keys %hseq) {
                    require Bio::Otter::Utils::AccessionInfo;
                    my $mm = Bio::Otter::Utils::AccessionInfo->new('db_categories' => $seq_db_list);
                    $accession_info = $mm->get_accession_info([keys %hseq]);
                    if (keys %{$accession_info}) {
                        $fasta_gff = ("##FASTA\n" . _fasta($accession_info));
                    }
                }
            }

            return $self->gff_header . $self->_features_gff($features, $accession_info) . $fasta_gff;
        });

    return;
}

sub sequence_database_list {
    my ($self) = @_;

    if (my $txt = $self->param('sequence_db')) {
        my $db_list = [ split /\s*,\s*/, $txt ];
        if (@$db_list) {
            return $db_list;
        }
    }
    return;
}

sub get_requested_features {

    my ($self) = @_;

    my @feature_kinds  = split(/,/, $self->require_argument('feature_kind'));
    foreach (@feature_kinds) {
        die "bad feature_kind $_" unless /^[_A-Za-z][_A-Za-z0-9]{1,63}$/;
    }
    my $analysis_list = $self->param('analysis');
    my @analysis_names = $analysis_list ? split(/,/, $analysis_list) : ( undef );
    my $filter_module = $self->param('filter_module');

    my $map = $self->make_map;
    my $feature_list = [];

    my $metakey = $self->param('metakey');
    ### Shouldn't loop where fetching method can take a list of analysis names.
    foreach my $analysis_name (@analysis_names) {
        foreach my $feature_kind (@feature_kinds) {
            my $getter_method = "get_all_${feature_kind}s";
            my $param_list =
                $feature_kind eq 'VariationFeature'
                ? [ undef, undef, undef, "${metakey}_variation" ]
                : $self->_param_list($analysis_name, $feature_kind);
            my $features = $self->fetch_mapped_features_ensembl($getter_method, $param_list, $map, $metakey);
            push @$feature_list, @$features;
        }
    }

    if ($filter_module) {

        # detaint the module string
        my ($module_name) = $filter_module =~ /^((\w+::)*\w+)$/;

        # for the moment be very conservative in what we allow
        if ($module_name =~ /^Bio::Vega::ServerAnalysis::\w+$/) {

            require_module($module_name);

            my $filter = $module_name->new;
            $filter->Web($self);

            warn scalar(@$feature_list) . " features before filtering...\n";
            $feature_list = $filter->run($feature_list);
            warn scalar(@$feature_list) . " features after filtering...\n";
        }
        else {
            die "Invalid filter module: '$filter_module'";
        }
    }

    # workaround: some of our pipelines put features on the wrong strand
    if ( $self->param('swap_strands') ) {
        for my $f (@$feature_list) {
            if ($f->can('hstrand') && $f->hstrand == -1) {
                $f->hstrand($f->hstrand * -1);
                $f->strand($f->strand * -1);
                $f->cigar_string(join '', reverse($f->cigar_string =~ /(\d*[A-Za-z])/g))
            }
        }
    }

    return $feature_list;
}

{

    my $call_args = {

        # EnsEMBL
        SimpleFeature => [
            ['analysis' => undef],
            ],
        RepeatFeature => [
            ['analysis' => undef],
            ['repeat_type' => undef],
            ['dbtype' => undef],
        ],
        MarkerFeature => [
            ['analysis' => undef],
            ['priority' => undef],
            ['map_weight' => undef],
        ],
        DitagFeature => [
            ['ditypes', undef, qr/,/],
            ['analysis' => undef],
        ],

        # Vega
        DnaDnaAlignFeature => [
            ['analysis' => undef],
            ['score' => undef],
            ['dbtype' => undef],
        ],
        DnaPepAlignFeature => [
            ['analysis' => undef],
            ['score' => undef],
            ['dbtype' => undef],
        ],
        PredictionTranscript => [
            ['analysis' => undef],
            ['load_exons' => 1],
        ],
        DnaSplicedAlignFeature => [
            ['analysis' => undef],
            ['score' => undef],
            ['dbtype' => undef],
        ],
        ProteinSplicedAlignFeature => [
            ['analysis' => undef],
            ['score' => undef],
            ['dbtype' => undef],
        ],

        # dummy
        ExonSupportingFeature => [
            ['analysis' => undef],
        ],

    };

    # Create list of arguments to EnsEMBL API fetching methods.
    # Need the right number of arguments in the right order.
    # Arguments are frequently undef.
    sub _param_list {
        my ($self, $analysis_name, $feature_kind) = @_;

        my @param_desc_list = @{ $call_args->{$feature_kind} };
        my $param_list = [];

        foreach my $desc (@param_desc_list) {
            my ($name, $value, $separator) = @$desc;

            # We used to do:
            #   $value = $self->require_argument($name) if @$desc == 1;
            # ie: A mandatory parameter in the otter config, but
            # there were no examples in the argument descriptions above.

            if ($name eq 'analysis') {
                # We don't call $self->param('analysis') becasue this can
                # be a comma separated list of analysis names
                $value = $analysis_name;
            }
            # Need defined test because value in otter config stanza may be 0
            elsif (defined(my $v = $self->param($name))) {
                if ($separator) {
                    # Parameter is a list
                    $value = [ split /$separator/, $v ];
                }
                else {
                    $value = $v;
                }
            }

            push @$param_list, $value;
        }

        return $param_list;
    }
}


sub gff_header {

    my ($self) = @_;

    my $gff_version = $self->param('gff_version');

    return Bio::Vega::Utils::GFF::gff_header($gff_version);
}

sub _features_gff {
    my ($self, $features, $accesion_info) = @_;

    my %gff_args = ();
    foreach my $key ($self->_gff_keys) {
        $gff_args{$key} = $self->param($key);
    }
    if ($accesion_info) {
        $gff_args{'accession_info'} = $accesion_info;
        $gff_args{'zmap_style_root'} = $self->param('zmap_style_root');
    }
    
    my $gff_version = $self->param('gff_version');
    $gff_args{'gff_format'} = Bio::Vega::Utils::GFF::gff_format($gff_version);

    my $url_string = delete $gff_args{'url_string'}; # not detainted yet, so delete it for now
    if (@$features) {           # don't bother unless there are some features
        if ($url_string) {
            my $url_fmt = detaint_sprintfn_url_fmt($url_string);
            die "Cannot detaint url_string='$url_string'" unless $url_fmt;
            $gff_args{'url_string'} = $url_fmt;      # reinstate detainted url_string
        }
        $gff_args{'species.url'} =
            $self->otter_dba->get_MetaContainer->single_value_by_key('species.url', 1);
    }

    my $features_gff = '';
    foreach my $feat (@$features) {
        $features_gff .= $feat->to_gff(%gff_args) || '';
    }

    return $features_gff;
};

sub _gff_keys {
    return @gff_keys;
}

# a Bio::EnsEMBL::Slice method to handle the dummy ExonSupportingFeature feature type
sub Bio::EnsEMBL::Slice::get_all_ExonSupportingFeatures {
    my ($self, $logic_name, $dbtype) = @_;

    my $load_exons = 1;

    if(!$self->adaptor()) {
        warning('Cannot get Transcripts without attached adaptor');
        return [];
    }

    my $ExonSupportingFeatures =
        [ map { @{$_->get_all_supporting_features} }
          map { @{$_->get_all_Exons} }
          @{$self->get_all_Transcripts($load_exons, $logic_name, $dbtype)}
          ];

    return $ExonSupportingFeatures;
}

sub _fasta {
    my ($accession_info) = @_;

    my $fasta = '';
    foreach my $name (sort keys %$accession_info) {
        $fasta .= _fasta_item($accession_info->{$name});
    }
    return $fasta;
}

sub _fasta_item {
    my ($accession_info) = @_;
    my $sequence = $accession_info->{sequence};

    my @taxon_list = split /,/, $accession_info->{'taxon_list'};
    # Take the first taxon ID which beings with a non-zero digit.
    # (Has side-effect of adding to $accession_info, but we don't mind.)
    ($accession_info->{'taxon_id'}) = grep { $_ != 0 } @taxon_list;

    $accession_info->{'description'} = escape_fasta_description($accession_info->{'description'}); # ---"---

    my $item = '>' . (join '|', map { $accession_info->{$_} } fasta_header_column_order() ) . "\n";
    while ($sequence =~ /(.{1,70})/g) {
        $item .= $1 . "\n";
    }
    return $item;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


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


package Bio::Otter::ServerAction::FindClones;

#
# A module used by server script 'find_clones' to find things on clones
# (new API version)
#

use strict;
use warnings;

use Try::Tiny;

use Bio::Otter::Utils::StableId;
use Bio::Vega::Utils::Attribute qw( get_first_Attribute_value );

use base 'Bio::Otter::ServerAction';

# Readonly seems to cause SIGSEGVs at exit, in conjunction with failing eval blocks.
# This is a shame.  I suspect only arrays and hashes are affected, but all are disabled to be safe.
# Global 'my' variables IN_CAPS should be Readonly.
#
# use Readonly;

my $WRAP_SEARCH_ERRORS    = 1;       # set this to 0 to aid command-line debugging

my $TARGET_COMPONENT_TYPE = 'clone'; # this is the type of components we want the found matches mapped on

my $MAX_TERMS = 50; # arbitrary limit to reduce DoS
my $MAX_HITS = 50; # approx, due to later find_by_* calls


sub new {
    my ($class, $server) = @_;

    my $self = $class->SUPER::new($server);

    $self->{_qnames}       = [ split ',', $server->require_argument('qnames') ];
    $self->{_results}      = {};
    $self->{_result_count} = 0;
    $self->{ coord_system_name } = $server->require_argument('coord_system_name');
    $self->{ coord_system_version } = $server->require_argument('coord_system_version');
    die "Too many query terms"
      if @{ $self->qnames } > $MAX_TERMS;

    return $self;
}

sub otter_dba {
    my ($self) = @_;
    return $self->{_otter_dba} ||=
        $self->server->dataset->otter_dba;
}

sub pipeline_dba {
    my ($self) = @_;
    return $self->{_pipeline_dba} ||=
        $self->server->dataset->pipeline_dba;
}

sub satellite_dba {
    my ($self, $metakey) = @_;
    return $self->{_satellite_dba}{$metakey} ||=
        $self->server->dataset->satellite_dba($metakey);
}

sub qnames {
    my ($self) = @_;
    return $self->{_qnames};
}

sub results {
    my ($self) = @_;
    return $self->{_results};
}

sub result_count {
    my ($self, $bump) = @_;
    return $self->{_result_count} += ($bump || 0);
}

my $FIND_CONTAINING_CHROMOSOMES_SQL_TEMPLATE = <<'SQL'
    SELECT    chr.name,
              group_concat(distinct a.cmp_seq_region_id) as joined_cmps
    FROM      assembly a,
              seq_region chr,
              coord_system cs
    WHERE     cs.name="%s"
    AND       cs.version="%s"
    AND       cs.coord_system_id=chr.coord_system_id
    AND       chr.seq_region_id=a.asm_seq_region_id
    AND       a.cmp_seq_region_id IN ( %s )
    GROUP BY  chr.name
SQL
    ;

sub find_containing_chromosomes {
    my ($self, $slice) = @_;

        # EnsEMBL as of rel46 cannot perform ambigous clone|subregion->contig->chromosome mapping correctly.
        # So we prefer to do it using direct SQL:

    my $sa = $slice->adaptor;

    # map the original slice onto contig_ids
    my $seq_level_slice_ids = [ $slice->coord_system->is_sequence_level
        ? $sa->get_seq_region_id($slice)
        : map { $sa->get_seq_region_id($_->to_Slice) } @{$slice->project('seqlevel')}
    ];

    # now map those contig_ids back onto a chromosome

    # cs must be alway chromosome, as this function is targeted to find chromosomes only.
    # Otherwise if we find non-chromosome - even search will work, client will not be able to open containing dataSet,
    # as it includes only chromosomes
    my $sql = sprintf
        $FIND_CONTAINING_CHROMOSOMES_SQL_TEMPLATE,
        'chromosome',
        $self->{ coord_system_version },
        (join ' , ', ('?') x @{$seq_level_slice_ids});
    my $sth = $sa->dbc->prepare($sql);
    $sth->execute(@{$seq_level_slice_ids});

    my @chr_slices = ();
    while( my ($atype, $joined_cmps) = $sth->fetchrow ) {
        my @cmps = split(/,/, $joined_cmps);
        if(scalar(@cmps) == scalar(@$seq_level_slice_ids)) {

            # let's hope the default coord_system_version is set correctly:
            my $chr_slice = $sa->fetch_by_region('chromosome', $atype);
            push @chr_slices, $chr_slice;
        }
    }

    return \@chr_slices;
}

sub register_slice {
    my ($self, $qname, $qtype, $slice) = @_;

    my $odba = $self->otter_dba;
    my $lsa = $odba->get_SliceAdaptor;
    my $sdba = $slice->adaptor->db;

    if($sdba == $odba) {
        $self->register_local_slice($qname, $qtype, $slice);
    } elsif($sdba == $self->pipeline_dba) {
        my $local_slice =
            $lsa->fetch_by_region(
                $slice->coord_system_name,
                $slice->seq_region_name,
                $slice->start,
                $slice->end,
                $slice->strand,
                $slice->coord_system->version,
            );
        $self->register_local_slice($qname, $qtype, $local_slice);
    } else {
        my $local_slices = $self->server->map_remote_slice_back($slice);
        foreach my $local_slice (@$local_slices) {
            $self->register_local_slice($qname, $qtype, $local_slice);
        }
    }

    return;
}

sub register_local_slice {
    my ($self, $qname, $qtype, $feature_slice) = @_;

    my $cs_name = $feature_slice->coord_system_name;

    my @component_names;
    my $found_chromosome_slices;

    if ($cs_name eq 'primary_assembly') {
            $found_chromosome_slices = [ $feature_slice ];
            @component_names = ( $feature_slice->seq_region_name );
    } elsif ($cs_name eq $TARGET_COMPONENT_TYPE) {
        @component_names = ( $feature_slice->seq_region_name );
    } else {
        # NOTE: order of projection segments WAS strand-dependent
        my @sorted_projections =
            sort { ($a->from_start <=> $b->from_start)*$feature_slice->strand }
                 @{ $feature_slice->project($TARGET_COMPONENT_TYPE) };

        @component_names = map { $_->to_Slice->seq_region_name } @sorted_projections;
    }

    if (! $found_chromosome_slices) {
        $found_chromosome_slices = ($cs_name eq 'chromosome')
            ? [ $feature_slice ]
            : $self->find_containing_chromosomes($feature_slice);
    }

    foreach my $chr_slice (@$found_chromosome_slices) {
        my $hidden = get_first_Attribute_value($chr_slice, 'hidden');
        next if $hidden;
        my $chr_name = $chr_slice->seq_region_name;
        my $key = join ',', @component_names;
        my $valref = \$self->results->{uc($qname)}->{$chr_name}->{$qtype}->{$key};

        my $value;
        if ($cs_name eq 'primary_assembly') {
            delete $self->results->{uc($qname)}->{$chr_name}->{$qtype}->{$key};
            $key = 'primary_assembly';
            $value = {
                'start' => $chr_slice->start,
                'end' => $chr_slice->end
            };
            $self->results->{uc($qname)}->{$chr_name}->{$qtype}->{$key} = $value;
            last;
        }

        if (!$$valref) {
            die "Too many hits" # will be caught per find_by_*
              if $self->result_count(1) > $MAX_HITS;
        } # else, already counted as a hit
        $$valref ++;
    }

    return;
}

sub find_by_otter_stable_ids {
    my ($self, @args) = @_;
    _wrap_search_errors($self, \&_find_by_otter_stable_ids, @args);
    return;
}

sub find_by_remote_stable_ids {
    my ($self, @args) = @_;
    _wrap_search_errors($self, \&_find_by_remote_stable_ids, @args);
    return;
}

my $ID_ADAPTOR_FETCHER_BY_TYPE = {
    'Gene' => [
        'gene_stable_id',
        'get_GeneAdaptor',
        'fetch_by_stable_id',
        ],
    'Transcript' => [
        'transcript_stable_id',
        'get_TranscriptAdaptor',
        'fetch_by_stable_id',
    ],
    'Translation' => [
        'translation_stable_id',
        'get_TranscriptAdaptor',
        'fetch_by_translation_stable_id',
    ],
    'Exon' => [
        'exon_stable_id',
        'get_ExonAdaptor',
        'fetch_by_stable_id',
    ],
};

sub _find_by_otter_stable_ids {
    my ($self) = @_;
    my $qtype_prefix = '';
    my $dba = $self->otter_dba;
    return $self->_find_by_stable_ids($dba, $qtype_prefix);
}

sub _find_by_remote_stable_ids {
    my ($self, $parameters) = @_;
    my ($qtype_prefix, $metakey) = @{$parameters};
    my $dba = $self->satellite_dba($metakey);
    return $self->_find_by_stable_ids($dba, $qtype_prefix);
}

sub _find_by_stable_ids {
    my ($self, $dba, $qtype_prefix) = @_;

    my $stable_id_utils = Bio::Otter::Utils::StableId->new($dba);

    foreach my $qname (@{$self->qnames}) {

        my $id_type = $stable_id_utils->type_for_id($qname);
        next unless $id_type;

        my $id_adaptor_fetcher = $ID_ADAPTOR_FETCHER_BY_TYPE->{$id_type};
        next unless $id_adaptor_fetcher;
        my ( $id, $adaptor, $fetcher ) = @{$id_adaptor_fetcher};

        # Just imagine: they raise an EXCEPTION to indicate nothing was found. Terrific!
        my $feature;
        try { $feature = $dba->$adaptor->$fetcher($qname); };
        next unless $feature;

        my $feature_slice  = $feature->feature_Slice;
        my $analysis_logic = $feature->analysis->logic_name;
        my $qtype = "${qtype_prefix}${analysis_logic}:${id}";
        $self->register_slice($qname, $qtype, $feature_slice);
    }

    return;
}

sub find_by_feature_attributes {
    my ($self, @args) = @_;
    _wrap_search_errors($self, \&_find_by_feature_attributes, @args);
    return;
}

my $FIND_BY_FEATURE_ATTRIBUTES_SQL_TEMPLATE = <<'SQL';
    SELECT %s, value
      FROM %s f JOIN %s a USING (%s) JOIN attrib_type t USING (attrib_type_id)
     WHERE code='%s'
       AND f.is_current=1
       AND ( %s )
SQL

sub _find_by_feature_attributes {
    my ($self, $parameters, $condition, $args) = @_;

    my ($qtype, $feat, $code, $adaptor_call) = @{$parameters};

    my $sql =
        sprintf $FIND_BY_FEATURE_ATTRIBUTES_SQL_TEMPLATE,
        $feat.'_id', $feat, $feat.'_attrib', $feat.'_id', $code, $condition;
    my $dbc = $self->otter_dba->dbc;
    my $sth = $dbc->prepare($sql);
    $sth->execute(@{$args});

    my $adaptor;
    while( my ($feature_id, $qname) = $sth->fetchrow ) {
        $adaptor ||= $self->otter_dba->$adaptor_call; # only do it if we found something
        my $feature = $adaptor->fetch_by_dbID($feature_id);
        $self->register_local_slice($qname, $qtype, $feature->feature_Slice);
    }

    return;
}

sub find_by_seqregion_names {
    my ($self, @args) = @_;
    _wrap_search_errors($self, \&_find_by_seqregion_names, @args);
    return;
}

my $FIND_BY_SEQREGION_NAMES_SQL_TEMPLATE = <<'SQL'
    SELECT cs.name, sr.name
      FROM seq_region sr, coord_system cs
     WHERE sr.coord_system_id=cs.coord_system_id
       AND cs.name <> 'chromosome'
       AND sr.name IN ( %s )
SQL
    ;

sub _find_by_seqregion_names {
    my ($self, $names) = @_;

    my $sql = sprintf
        $FIND_BY_SEQREGION_NAMES_SQL_TEMPLATE,
        (join ' , ', ('?') x @{$names});
    my $dbc = $self->otter_dba->dbc;
    my $sth = $dbc->prepare($sql);
    $sth->execute(@{$names});

    my $adaptor;
    while( my ($cs_name, $sr_name) = $sth->fetchrow ) {
        $adaptor ||= $self->otter_dba->get_SliceAdaptor;
        my $slice = $adaptor->fetch_by_region($cs_name, $sr_name);
        $self->register_local_slice($sr_name, $cs_name.'_name', $slice);
    }

    return;
}

sub find_by_seqregion_attributes {
    my ($self, @args) = @_;
    _wrap_search_errors($self, \&_find_by_seqregion_attributes, @args);
    return;
}

my $FIND_BY_SEQREGION_ATTRIBUTES_SQL_TEMPLATE = <<'SQL'
    SELECT sr.name, sra.value
      FROM seq_region sr, coord_system cs, seq_region_attrib sra
     WHERE cs.name = '%s'
       AND sr.coord_system_id = cs.coord_system_id
       AND sr.seq_region_id = sra.seq_region_id
       AND sra.attrib_type_id = (SELECT attrib_type_id from attrib_type where code = '%s')
       AND sra.value IN ( %s )
SQL
    ;

sub _find_by_seqregion_attributes {
    my ($self, $parameters, $names) = @_;

    my ($qtype, $cs_name, $code) = @{$parameters};

    my $sql = sprintf
        $FIND_BY_SEQREGION_ATTRIBUTES_SQL_TEMPLATE,
        $cs_name, $code, (join ' , ', ('?') x @{$names});
    my $dbc = $self->otter_dba->dbc;
    my $sth = $dbc->prepare($sql);
    $sth->execute(@{$names});

    my $adaptor;
    while( my ($sr_name, $qname) = $sth->fetchrow ) {
        $adaptor ||= $self->otter_dba->get_SliceAdaptor;
        my $slice = $adaptor->fetch_by_region($cs_name, $sr_name);
        $self->register_local_slice($qname, $qtype, $slice);
    }

    return;
}

sub find_by_xref {
    my ($self, @args) = @_;
    _wrap_search_errors($self, \&_find_by_xref, @args);
    return;
}

my $FIND_BY_XREF_SQL_TEMPLATE = <<'SQL'
    SELECT DISTINCT
            edb.db_name
          , x.dbprimary_acc
          , sr.name
          , cs.name
          , cs.version
          , (CASE ox.ensembl_object_type
            WHEN 'Gene' THEN g.seq_region_start
            WHEN 'Transcript' THEN t.seq_region_start
            WHEN 'Translation' THEN t2p.seq_region_start END)
          , (CASE ox.ensembl_object_type
            WHEN 'Gene' THEN g.seq_region_end
            WHEN 'Transcript' THEN t.seq_region_end
            WHEN 'Translation' THEN t2p.seq_region_end END)
    FROM (external_db edb
          , xref x
          , object_xref ox)
    LEFT JOIN gene g
      ON g.gene_id = ox.ensembl_id
    LEFT JOIN transcript t
      ON t.transcript_id = ox.ensembl_id
    LEFT JOIN translation p
      ON p.translation_id = ox.ensembl_id
    LEFT JOIN transcript t2p
      ON p.transcript_id = t2p.transcript_id
    LEFT JOIN seq_region sr
      ON sr.seq_region_id = (CASE ox.ensembl_object_type
        WHEN 'Gene' THEN g.seq_region_id
        WHEN 'Transcript' THEN t.seq_region_id
        WHEN 'Translation' THEN t2p.seq_region_id END)
    LEFT JOIN coord_system cs
      ON cs.coord_system_id = sr.coord_system_id
    WHERE edb.external_db_id = x.external_db_id
      AND x.xref_id = ox.xref_id
      AND x.dbprimary_acc IN ( %s )
SQL
    ;

sub _find_by_xref {
    my ($self, $parameters, $names) = @_;

    my ($prefix, $metakey) = @{$parameters};

    my $satellite_dba = $self->satellite_dba($metakey);

    my $sql = sprintf
        $FIND_BY_XREF_SQL_TEMPLATE,
        (join ' , ', ('?') x @{$names});
    my $dbc = $satellite_dba->dbc;
    my $sth = $dbc->prepare($sql);
    $sth->execute(@{$names});

    my $adaptor;
    while( my ($db_name, $qname, $sr_name, $cs_name, $cs_version, $start, $end) = $sth->fetchrow ) {
        $adaptor ||= $satellite_dba->get_SliceAdaptor;
        my $slice = $adaptor->fetch_by_region($cs_name, $sr_name, $start, $end, 1, $cs_version);
        my $qtype = "${prefix}${db_name}:";
        $self->register_slice($qname, $qtype, $slice);
    }

    return;
}

sub find_by_hit_name {
    my ($self, @args) = @_;
    _wrap_search_errors($self, \&_find_by_hit_name, @args);
    return;
}

my $FIND_BY_HIT_NAME_SQL_TEMPLATE = <<'SQL'
    SELECT af.hit_name
         , sr.name
         , cs.name
         , cs.version
         , af.seq_region_start
         , af.seq_region_end
         , af.seq_region_strand
         , a.logic_name
         , SUM(af.score) score_sum
      FROM %s af
         , seq_region sr
         , coord_system cs
         , analysis a
     WHERE af.seq_region_id = sr.seq_region_id
       AND cs.coord_system_id = sr.coord_system_id
       AND a.analysis_id = af.analysis_id
       AND af.hit_name IN ( %s )
     GROUP BY af.hit_name, af.seq_region_id
     ORDER BY score_sum DESC
     LIMIT 10
SQL
    ;

sub _find_by_hit_name {
    my ($self, $parameters, $names) = @_;

    my ($kind) = @{$parameters};

    ## kind = 'dna'|'protein'
    #
    my $table_name = $kind.'_align_feature';

    my $pipe_dba = $self->pipeline_dba;

    my $sql = sprintf
        $FIND_BY_HIT_NAME_SQL_TEMPLATE,
        $table_name, (join ' , ', ('?') x @{$names});
    my $dbc = $pipe_dba->dbc;
    my $sth = $dbc->prepare($sql);
    $sth->execute(@{$names});

    my $adaptor;
    while( my ($qname, $sr_name, $cs_name, $cs_version,
               $start, $end, $strand, $analysis_name, $score)
           = $sth->fetchrow ) {
        $adaptor ||= $pipe_dba->get_SliceAdaptor;
        my $slice = $adaptor->fetch_by_region(
            $cs_name, $sr_name, $start, $end, $strand, $cs_version);
        my $qtype = "Pipeline_${kind}_hit:${analysis_name}(score=$score)";
        $self->register_slice($qname, $qtype, $slice);
    }

    return;
}

my @REMOTE_STABLE_IDS_PARAMETERS = (
    #     prefix       metakey
    [ qw( EnsEMBL:     ensembl_core_db_head    ) ],
    [ qw( EnsEMBL_EST: ensembl_estgene_db_head ) ],
    );

my @HIT_NAME_PARAMETERS = (
    #     kind
    [ qw( dna     ) ],
    [ qw( protein ) ],
    );

my @XREF_PARAMETERS = (
    #     prefix,  metakey
    [ qw( CCDS_db: ens_livemirror_ccds_db ) ],
    );

my @FEATURE_ATTRIBUTES_PARAMETERS = (
    #     qtype           feature    code    adaptor
    [ qw( gene_name       gene       name    get_GeneAdaptor       ) ],
    [ qw( gene_synonym    gene       synonym get_GeneAdaptor       ) ],
    [ qw( transcript_name transcript name    get_TranscriptAdaptor ) ],
    );

my @FEATURE_ATTRIBUTES_PREFIXES = qw( WU );
# Plain gene & transcript names 'foo' also search these 'prefix:foo'.
#
# Hardwired because obtaining a live set of current prefixes is slow.
# Don't want to maintain an explicit cache.
#
# Many prefixes (KO, LOF) will co-occur with the plain name, so it is
# less important to search for them when not requested.

my @SEQREGION_ATTRIBUTES_PARAMETERS = (
    #     qtype,                   cs_name code
    [ qw( international_clone_name clone   intl_clone_name ) ],
    [ qw( clone_accession          clone   embl_acc        ) ],
    );

sub find {
    my ($self) = @_;

    # lists of names, with and without versions
    my $names = $self->qnames;
    my $names_2 = [ _strip_trailing_version_numbers(@{$names}) ];

    ### conditions and arguments for find_by_feature_attributes
    #
    # LIKE uses the fast (left-anchored) index.  RLIKE and
    # left-wildcard LIKE cannot.
    #
    # Chose speed.  Support wildcards, search only for known prefixes
    # unless requested.
    my @fa_name = map { __fa_add_prefixes($_) }
      map { __fa_add_dupsfx($_) } @{$names};
    my $fa_args = [ map { __tamecard_like($_) } @fa_name ];
    my $fa_condition = join ' OR ', (('( value LIKE ? )') x @$fa_args);

    $self->find_by_seqregion_names($names);

    $self->find_by_otter_stable_ids;
    $self->find_by_remote_stable_ids($_) for @REMOTE_STABLE_IDS_PARAMETERS;
    $self->find_by_hit_name($_, $names) for @HIT_NAME_PARAMETERS;
    $self->find_by_xref($_, $names_2) for @XREF_PARAMETERS;
    $self->find_by_feature_attributes($_, $fa_condition, $fa_args) for @FEATURE_ATTRIBUTES_PARAMETERS;
    $self->find_by_seqregion_attributes($_, $names) for @SEQREGION_ATTRIBUTES_PARAMETERS;

    return;
}

sub result_overflow {
    my ($self) = @_;
    return $self->result_count > $MAX_HITS;
}

sub find_clones {
    my ($self) = @_;
    $self->find;
    my $output = $self->serialise_output($self->results);
    return $output;
}

# Null serialiser, overridden in B:O:SA:TSV::FindClones
sub serialise_output {
    my ($self, $results) = @_;
    return $results;
}

sub _wrap_search_errors {
    my ($self, $coderef, @args) = @_;
    if ($WRAP_SEARCH_ERRORS) {
        try { $self->$coderef(@args); return 1; } or return;
    }
    else {
        $self->$coderef(@args);
    }
    return;
}

# these are private subroutines, *not* methods

sub _strip_trailing_version_numbers { ## no critic (Subroutines::RequireArgUnpacking)
    return map { /^(.*?)(?:\.[[:digit:]]+)?$/ } @_;
}

# add prefixed versions of plain names
sub __fa_add_prefixes {
    my ($n) = @_;
    return (($n =~ /:|^\*/)
            ? ($n)
            : ($n, map { "$_:$n" } @FEATURE_ATTRIBUTES_PREFIXES));
}

# add de-duping suffix, unless we have suffix
sub __fa_add_dupsfx {
    my ($n) = @_;
    return (($n =~ /_|\*$/)
            ? ($_)
            : ($_, $_.'_*'));
}

# implement the *-as-wildcard for LIKE
sub __tamecard_like {
    my ($n) = @_;
    # MySQL backslashing rules say to pair them to quench C-style
    # escaping, but placeholders don't need that.  Then backslash
    # escapes one LIKE metacharacter.

    $n =~ s{\\}{\x5c\x5c}g;   # literal backslash in LIKE
    $n =~ s{([_%])}{\x5c$1}g; # literal _ and %

    # We offer * as wildcard
    $n =~ s{\*}{%}g;

    return $n;
}


1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

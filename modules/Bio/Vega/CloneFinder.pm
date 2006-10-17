package Bio::Vega::CloneFinder;

use strict;
use Bio::Otter::Lace::Locator;

my $component = 'clone';

#
# A module used by server script 'find_clones' to find things on clones
# (new API version)
#

use strict;

my $DEBUG=0; # do not show all SQL statements

sub new {
    my ($class, $dba, $qnames) = @_;

    my $self = bless {
        '_dba' => $dba,
        '_ql'  => ($qnames ? {map {($_ => [])} @$qnames } : {}),
    }, $class;

    return $self;
}

sub dba {
    my $self = shift @_;

    return $self->{_dba};
}

sub dbc {
    my $self = shift @_;

    return $self->dba->dbc();
}

sub qnames_locators {
#
# This is a HoL
# {query_name}[locators*]
#
    my $self = shift @_;

    return $self->{_ql};
}

sub register_feature {
    my ($self, $qname, $qtype, $feature) = @_;

    my $loc = Bio::Otter::Lace::Locator->new($qname, $qtype);

    my $cs_name = $feature->isa('Bio::EnsEMBL::Slice')
        ? $feature->coord_system_name()
        : $feature->slice()->coord_system_name();
    my $sr_name = $feature->seq_region_name();

    $loc->assembly( ($cs_name eq 'chromosome')
        ? $sr_name
            # NOTE: the mapping of features on clones may not be unique. Solutions?
        : $feature->project('chromosome', 'Otter')->[0]->to_Slice()->seq_region_name()
    );

    $loc->component_names( ($cs_name eq $component)
        ? [ $sr_name ]
            # NOTE: we hope that the mapping is ordered. If not, we can order it.
        : [ map { $_->to_Slice()->seq_region_name() } @{ $feature->project($component) } ]
    );

    my $locs = $self->qnames_locators()->{$qname} ||= [];
    push @$locs, $loc;
}

sub find_by_stable_ids {
    my $self = shift @_;

    my $dba      = $self->dba();
    my $meta_con = $dba->get_MetaContainer();

    my $prefix_primary = $meta_con->get_primary_prefix()
        || die "Missing prefix.primary in meta table";

    my $prefix_species = $meta_con->get_species_prefix()
        || die "Missing prefix.species in meta table";

    my $gene_adaptor           = $dba->get_GeneAdaptor();
    my $transcript_adaptor     = $dba->get_TranscriptAdaptor();
    my $exon_adaptor           = $dba->get_ExonAdaptor();

    foreach my $qname (keys %{$self->qnames_locators()}) {
        if(uc($qname) =~ /^$prefix_primary$prefix_species([TPGE])\d+/i){ # try stable_ids
            my $typeletter = $1;
            my $qtype;
            my $feature;

            eval {
                if($typeletter eq 'G') {
                    $qtype = 'gene_stable_id';
                    $feature = $gene_adaptor->fetch_by_stable_id($qname);
                } elsif($typeletter eq 'T') {
                    $qtype = 'transcript_stable_id';
                    $feature = $transcript_adaptor->fetch_by_stable_id($qname);
                } elsif($typeletter eq 'P') {
                    $qtype = 'translation_stable_id';
                    $feature = $transcript_adaptor->fetch_by_translation_stable_id($qname);
                } elsif($typeletter eq 'E') {
                    $qtype = 'exon_stable_id';
                    $feature = $exon_adaptor->fetch_by_stable_id($qname);
                }
            };
                # Just imagine: they raise an EXCEPTION to indicate nothing was found. Terrific!
            if($@) {
                # server_log("'$qname' looks like a stable id, but wasn't found.");
                # server_log($@)if $DEBUG;
            } else {
                $self->register_feature($qname, $qtype, $feature);
            }
        }
    } # foreach $qname
}

sub find_by_feature_attributes {
    my ($self, $quoted_qnames, $table, $id_field, $code_hash, $adaptor_call) = @_;

    my $dbc      = $self->dbc();
    my $adaptor;

    while( my ($code,$qtype) = each %$code_hash ) {
        my $sql = qq{
            SELECT $id_field, value
            FROM $table
            WHERE attrib_type_id = (SELECT attrib_type_id from attrib_type where code='$code')
              AND value in ($quoted_qnames)
        };

        my $sth = $dbc->prepare($sql);
        $sth->execute();
        while( my ($feature_id, $qname) = $sth->fetchrow() ) {
            $adaptor ||= $self->dba()->$adaptor_call; # only do it if we found something

            my $feature = $adaptor->fetch_by_dbID($feature_id);

            $self->register_feature($qname, $qtype, $feature);
        }
    }
}

sub find_by_seqregion_names {
    my ($self, $quoted_qnames) = @_;

    my $dbc      = $self->dbc();
    my $adaptor;

    my $sql = qq{
        SELECT cs.name, sr.name
        FROM seq_region sr, coord_system cs
        WHERE sr.coord_system_id=cs.coord_system_id
          AND cs.name <> 'chromosome'
          AND sr.name in ($quoted_qnames)
    };

    my $sth = $dbc->prepare($sql);
    $sth->execute();
    while( my ($cs_name, $sr_name) = $sth->fetchrow() ) {
        $adaptor ||= $self->dba()->get_SliceAdaptor();

        my $slice = $adaptor->fetch_by_region($cs_name, $sr_name);

        $self->register_feature($sr_name, $cs_name.'_name', $slice);
    }
}

sub find_by_seqregion_attributes {
    my ($self, $quoted_qnames, $cs_name, $code_hash) = @_;

    my $dbc      = $self->dbc();
    my $adaptor;

    while( my ($code,$qtype) = each %$code_hash ) {
        my $sql = qq{
            SELECT sr.name, sra.value
            FROM seq_region sr, coord_system cs, seq_region_attrib sra
            WHERE cs.name='$cs_name'
              AND sr.coord_system_id=cs.coord_system_id
              AND sr.seq_region_id=sra.seq_region_id
              AND sra.attrib_type_id = (SELECT attrib_type_id from attrib_type where code='$code')
              AND sra.value in ($quoted_qnames)
        };

        my $sth = $dbc->prepare($sql);
        $sth->execute();
        while( my ($sr_name, $qname) = $sth->fetchrow() ) {
            $adaptor ||= $self->dba()->get_SliceAdaptor();

            my $slice = $adaptor->fetch_by_region($cs_name, $sr_name);

            $self->register_feature($qname, $qtype, $slice);
        }
    }
}

sub find {
    my ($self, $unhide) = @_;

    my $quoted_qnames = join(', ', map {"'$_'"} keys %{$self->qnames_locators()} );

    $self->find_by_stable_ids();

    $self->find_by_seqregion_names($quoted_qnames);

    $self->find_by_feature_attributes($quoted_qnames, 'gene_attrib', 'gene_id',
        { 'name' => 'gene_name', 'synonym' => 'gene_synonym'},
        'get_GeneAdaptor');

    $self->find_by_feature_attributes($quoted_qnames, 'transcript_attrib', 'transcript_id',
        { 'name' => 'transcript_name'},
        'get_TranscriptAdaptor');

    $self->find_by_seqregion_attributes($quoted_qnames, 'clone',
        { 'intl_clone_name' => 'international_clone_name', 'embl_acc' => 'clone_accession' },
        );
}

sub generate_output {
    my ($self, $filter_atype) = @_;

    my $output_string = '';

    for my $qname (sort keys %{$self->qnames_locators()}) {
        my $locators = $self->qnames_locators()->{$qname};
        my $count = 0;
        for my $loc (@$locators) {
            my $asm = $loc->assembly();
            if(!$filter_atype || ($filter_atype eq $asm)) {
                $output_string .= join("\t",
                    $qname, $loc->qtype(),
                    join(',', @{$loc->component_names()}),
                    $loc->assembly())."\n";
                $count++;
            }
        }
        if(!$count) {
            $output_string .= "$qname\n"; # no matches for this qname
        }
    }

    return $output_string;
}

1;


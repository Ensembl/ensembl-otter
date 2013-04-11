# Dummy B:O:Lace::Client

package OtterTest::Client;

use strict;
use warnings;

use Bio::Otter::Lace::Client;   # _build_meta_hash
use Bio::Otter::Utils::MM;
use Bio::Otter::Server::Config;

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub get_accession_types {
    my ($self, @accessions) = @_;
    my $types = $self->mm->get_accession_types(\@accessions);
    # FIXME: de-serialisation is in wrong place: shouldn't need to serialise here.
    # see apache/get_accession_types and AccessionTypeCache.
    my $response = '';
    foreach my $acc (keys %$types) {
        $response .= join("\t", $acc, @{$types->{$acc}}) . "\n";
    }
    return $response;
}

sub mm {
    my $self = shift;
    return $self->{_mm} ||= Bio::Otter::Utils::MM->new;
}

# FIXME: scripts/apache/get_config needs reimplementing with a Bio::Otter::ServerAction:: class,
#        which we can then use here rather than duplicating the file names.
#
sub get_otter_schema {
    my $self = shift;
    return Bio::Otter::Server::Config->get_file('otter_schema.sql');
}

sub get_loutre_schema {
    my $self = shift;
    return Bio::Otter::Server::Config->get_file('loutre_schema_sqlite.sql');
}

sub get_meta {
    my $self = shift;
    my $response = $self->_meta_response;
    return $self->Bio::Otter::Lace::Client::_build_meta_hash($response);
}

sub get_db_info {
    return { 'coord_system.chromosome' => [ 2, 1, 'chromosome', 'Otter', 2, 'default_version' ] };
}

sub _meta_response {
    my $self = shift;
    my $response = $self->_meta_response_embedded;
    $response =~ s|//|\t|g;
    return $response;
}

sub _meta_response_embedded {
    # NB: field separator is //, trailing separators are intentional.
    return << '_EO_RESPONSE_';
schema_version//70//
patch//patch_40_41_a.sql|analysis_description_displayable//
patch//patch_40_41_b.sql|info_type_enum//
patch//patch_40_41_c.sql|xref_priority//
patch//patch_40_41_d.sql|ditag_primary_key_type//
patch//patch_40_41_e.sql|schema_version//
patch//patch_40_41_f.sql|attrib_indices//
assembly.mapping//clone#contig//1
prefix.species//HUM//1
patch//patch_41_42_a.sql|remove_xref_priority//
patch//patch_41_42_c.sql|analysis_description_unique//
patch//patch_41_42_d.sql|schema_version//
patch//patch_41_42_e.sql|ditag_autoincrement//
patch//patch_41_42_f.sql|analysis_description_web_data//
patch//patch_41_42_g.sql|genebuild_version_format_change//
patch//patch_41_42_b.sql|unconventional_transcripts//
species.display_name//Human//1
species.taxonomy_id//9606//1
species.common_name//human//1
species.classification//sapiens//1
species.classification//Homo//1
species.classification//Hominidae//1
species.classification//Catarrhini//1
species.classification//Haplorrhini//1
species.classification//Primates//1
species.classification//Euarchontoglires//1
species.classification//Eutheria//1
species.classification//Mammalia//1
species.classification//Euteleostomi//1
species.classification//Vertebrata//1
species.classification//Craniata//1
species.classification//Chordata//1
species.classification//Metazoa//1
species.classification//Eukaryota//1
patch//patch_42_43_a.sql|unmapped_object.parent//
patch//patch_42_43_b.sql|unmapped_object_probe2transcript//
patch//patch_42_43_c.sql|info_type_probe_unmapped//
patch//patch_42_43_d.sql|unmapped_object_external_db_id//
patch//patch_42_43_e.sql|gene_archive.peptide_archive_id.index//
patch//patch_42_43_f.sql|schema_version//
patch//patch_43_44_a.sql|rationalise_key_columns//
patch//patch_43_44_b.sql|optimise_ditag_tables//
patch//patch_43_44_c.sql|external_db_type//
patch//patch_43_44_d.sql|translation_stable_id_unique//
patch//patch_43_44_e.sql|schema_version//
patch//patch_43_44_f.sql|external_db_type_syn//
patch//patch_44_45_a.sql|schema_version//
patch//patch_44_45_b.sql|marker_index//
patch//patch_44_45_c.sql|db_release_not_null//
patch//patch_45_46_a.sql|schema_version//
patch//patch_45_46_b.sql|go_xref.source_xref_id//
patch//patch_45_46_c.sql|unmapped_object.external_db_id//
patch//patch_45_46_d.sql|meta_unique_key//
patch//patch_45_46_e.sql|external_db_new_cols//
patch//patch_45_46_f.sql|stable_id_event.uni_idx//
patch//patch_45_46_g.sql|object_xref_linkage_annotation//
prefix.primary//OTT//1
assembly.mapping//subregion#contig//1
assembly.mapping//chromosome:Otter#chromosome:NCBI36//1
patch//patch_46_47_a.sql|schema_version//
patch//patch_46_47_b.sql|new_align_columns//
patch//patch_46_47_c.sql|extend_db_release//
patch//patch_47_48_a.sql|schema_version//
patch//patch_48_49_a.sql|schema_version//
patch//patch_48_49_b.sql|new_canonical_transcript_column//
patch//patch_48_49_c.sql|regulatory_support_removal//
patch//patch_48_49_d.sql|new_info_type_enum//
patch//patch_48_49_e.sql|ensembl_object_type_not_null//
assembly.mapping//chromosome:Otter#contig//1
assembly.mapping//chromosome:NCBI36#contig//1
assembly.mapping//chromosome:Otter#contig#clone//1
assembly.mapping//chromosome:NCBI36#contig#clone//1
patch//patch_49_50_a.sql|schema_version//
patch//patch_49_50_b.sql|coord_system_version_default//
patch//patch_49_50_c.sql|canonical_transcript//
patch//patch_49_50_d.sql|seq_region_indices//
patch//patch_49_50_e.sql|mapping_seq_region//
patch//patch_50_51_a.sql|schema_version//
patch//patch_50_51_b.sql|protein_feature_hit_name//
patch//patch_50_51_c.sql|meta_coord_index//
patch//patch_50_51_d.sql|multispecies//
patch//patch_50_51_e.sql|feature_external_data//
patch//patch_50_51_f.sql|meta_species_id_values//
patch//patch_50_51_g.sql|protein_feature_score//
patch//patch_50_51_h.sql|external_db_db_name//
patch//patch_50_51_i.sql|meta_value_binary//
assembly.mapping//chromosome:OtterArchive#contig//1
assembly.mapping//chromosome:OtterArchive#contig#clone//1
patch//patch_51_52_a.sql|schema_version//
patch//patch_51_52_b.sql|widen_columns//
patch//patch_51_52_c.sql|pair_dna_align_feature_id//
patch//patch_51_52_d.sql|external_db_description//
patch//patch_52_53_a.sql|schema_version//
patch//patch_52_53_b.sql|external_db_type_enum//
patch//patch_52_53_d.sql|drop_go_xref_index//
patch//patch_52_53_c.sql|identity_xref_rename//
patch//patch_53_54_a.sql|schema_version//
patch//patch_53_54_b.sql|widen_columns//
patch//patch_53_54_c.sql|identity_object_analysis_move//
patch//patch_54_55_a.sql|schema_version//
patch//patch_54_55_b.sql|add_go_xrefs_types//
patch//patch_54_55_c.sql|add_splicing_event_tables//
patch//patch_54_55_d.sql|add_dependent_xref_table//
patch//patch_54_55_e.sql|add_is_constitutive_column//
patch//patch_54_55_f.sql|coord_system.version_null//
patch//patch_54_55_g.sql|analysis_description.display_label_NOT_NULL//
patch//patch_54_55_h.sql|gene_archive.allow_for_NULLs//
assembly.mapping//chromosome:GRCh37#contig//1
assembly.mapping//chromosome:GRCh37#contig#clone//1
assembly.mapping//chromosome:Otter#chromosome:GRCh37//1
assembly.mapping//chromosome:Otter#chromosome:OtterArchive//1
patch//patch_55_56_a.sql|schema_version//
patch//patch_55_56_b.sql|add_index_names//
patch//patch_55_56_c.sql|drop_oligo_tables_and_xrefs//
patch//patch_55_56_d.sql|add_index_to_splicing_event_feature//
patch//patch_56_57_a.sql|schema_version//
patch//patch_56_57_b.sql|unmapped_object.typ_enum_tidy//
patch//patch_56_57_c.sql|external_db_type_enum//
patch//patch_56_57_d.sql|allow_meta_null//
patch//patch_56_57_e.sql|canonical_translations//
patch//patch_56_57_f.sql|simple_feature.display_label//
patch//patch_57_58_a.sql|schema_version//
patch//patch_58_59_a.sql|schema_version//
patch//patch_58_59_b.sql|assembly_exception_exc_type_enum//
patch//patch_58_59_c.sql|splicing_event_attrib_type_id//
patch//patch_58_59_d.sql|object_xref_extend_index//
schema_type//core//
patch//patch_58_59_e.sql|meta_schema_type//
patch//patch_59_60_a.sql|schema_version//
patch//patch_59_60_b.sql|rename_go_xref_table//
patch//patch_59_60_c.sql|QC_fixes//
species.production_name//homo_sapiens//1
patch//patch_60_61_a.sql|schema_version//
patch//patch_60_61_b.sql|create_seq_region_synonym_table//
patch//patch_60_61_c.sql|rejig_object_xref_indexes//
patch//patch_61_62_a.sql|schema_version//
patch//patch_61_62_b.sql|synonym_field_extension//
patch//patch_61_62_c.sql|db_name_db_release_idx//
patch//patch_61_62_d.sql|remove_display_label_linkable//
patch//patch_61_62_e.sql|seq_region_synonym_seq_region_idx//
patch//patch_62_63_a.sql|schema_version//
patch//patch_62_63_b.sql|indexing_changes//
patch//patch_62_63_c.sql|remove_dbprimary_acc_linkable//
patch//patch_63_64_a.sql|schema_version//
patch//patch_63_64_b.sql|add_operons//
patch//patch_63_64_c.sql|is_ref_added_to_alt_allele//
patch//patch_63_64_d.sql|linkage_type change in ontology_xref//
species.scientific_name//Homo sapiens//1
species.url//Homo_sapiens//1
patch//patch_64_65_a.sql|schema_version//
patch//patch_64_65_b.sql|merge_stable_id_with_object//
patch//patch_64_65_c.sql|add_data_file//
patch//patch_64_65_d.sql|add_checksum_info_type//
patch//patch_65_66_a.sql|schema_version//
patch//patch_65_66_b.sql|fix_external_db_id//
patch//patch_65_66_c.sql|reorder_unmapped_obj_index//
patch//patch_65_66_d.sql|add_index_to_ontology_xref_table//
patch//patch_65_66_e.sql|fix_external_db_id_in_xref//
patch//patch_65_66_f.sql|drop_default_values//
patch//patch_66_67_a.sql|schema_version//
patch//patch_66_67_b.sql|drop_stable_id_views//
patch//patch_66_67_c.sql|adding_intron_supporting_evidence//
patch//patch_66_67_d.sql|adding_gene_transcript_annotated//
patch//patch_66_67_e.sql|index_canonical_transcript_id//
patch//patch_67_68_a.sql|schema_version//
patch//patch_67_68_b.sql|xref_uniqueness//
patch//patch_67_68_c.sql|altering_intron_supporting_evidence//
patch//patch_67_68_d.sql|add_is_splice_canonical_and_seq_index//
patch//patch_67_68_e.sql|fix_67_68_e_xref_index//
patch//patch_68_69_a.sql|schema_version//
patch//patch_69_70_a.sql|schema_version//
patch//patch_69_70_b.sql|add_mapping_set_history//
patch//patch_69_70_c.sql|column_datatype_consistency//
patch//patch_69_70_d.sql|data_file_id_auto_increment//
patch//patch_69_70_e.sql|protein_feature_hit_description//
_EO_RESPONSE_
}

1;

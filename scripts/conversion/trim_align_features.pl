# create temporary tables (daf_tmp, paf_tmp) with entries in daf/paf with score
# < 80 which are used in supporting_feature
create table daf_tmp select daf.* from dna_align_feature daf,
supporting_feature sf where sf.feature_type = 'dna_align_feature' and
sf.feature_id = daf.dna_align_feature_id and daf.score < 80;

create table paf_tmp select daf.* from protein_align_feature daf,
supporting_feature sf where sf.feature_type = 'protein_align_feature' and
sf.feature_id = daf.protein_align_feature_id and daf.score < 80;

# delete from daf/paf where score < 80
delete from dna_align_feature where score < 80;
delete from protein_align_feature where score < 80;

# optimize tables
optimize table dna_align_feature;
optimize table protein_align_feature;
optimize table repeat_feature;
optimize table repeat_consensus;
optimize table dna;

# copy daf_tmp/paf_tmp back into daf/paf
insert ignore into dna_align_feature select * from daf_tmp;
insert ignore into protein_align_feature select * from paf_tmp;

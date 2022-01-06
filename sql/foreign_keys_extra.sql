-- Copyright [2018-2022] EMBL-European Bioinformatics Institute
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

# This foreign key constraints are not used in real databases, but are
# handy for causing DbVisualizer to draw connections between tables
# and start the layout process.
#
# For this use I have taken some liberties in applying as many
# constraints as possible.
#
# This file applies to loutre_mouse "schema_version 57".  See also
#   http://cvs.sanger.ac.uk/cgi-bin/viewvc.cgi/ensembl/sql/foreign_keys.sql?root=ensembl&view=log
#   http://cvs.sanger.ac.uk/cgi-bin/viewvc.cgi/ensembl/sql/table.sql?root=ensembl&view=log




### For EnsEMBL schema

# bugfix?  add FKable index
ALTER TABLE mapping_set ADD UNIQUE INDEX (mapping_set_id);

# bugfix?  add UNSIGNED to all cols
ALTER TABLE dependent_xref
 MODIFY COLUMN object_xref_id INTEGER UNSIGNED NOT NULL,
 MODIFY COLUMN master_xref_id INTEGER UNSIGNED NOT NULL AUTO_INCREMENT,
 MODIFY COLUMN dependent_xref_id INTEGER UNSIGNED NOT NULL;


# There is no species table or species_id PK, but we can reference in
# either direction just to join the table onto the schema graph
#
#ALTER TABLE meta ADD FOREIGN KEY (species_id) REFERENCES coord_system(species_id);
ALTER TABLE coord_system ADD FOREIGN KEY (species_id) REFERENCES meta(species_id);


# gene_archive.{gene,transcript,translation}_{stable_id,version} -> ?
# splicing_event_feature.transcript_association -> ?
# mapping_session.? -> mapping_set.?



### For Loutre schema

# Exclusive arc: supporting_feature.feature_id --> ( protein_align_feature | dna_align_feature )
# Exclusive arc?  unmapped_object.ensembl_id --> ???

ALTER TABLE contig_lock MODIFY COLUMN author_id INT(10) UNSIGNED NOT NULL DEFAULT 0;

# tmp_align -- should have been dropped after remapping seq_regions
# test_contig_info
# gene_name_update.consortium_id -> ?
# gene_name_update.old_name -> mapping_session ?
# interpro
# {translation,transcript,gene,exon}_stable_id_pool  ?

ALTER TABLE assembly_tag ADD FOREIGN KEY (seq_region_id) REFERENCES seq_region(seq_region_id);

ALTER TABLE contig_lock ADD FOREIGN KEY (seq_region_id) REFERENCES seq_region(seq_region_id);
ALTER TABLE contig_lock ADD FOREIGN KEY (author_id) REFERENCES author(author_id);

ALTER TABLE contig_info ADD FOREIGN KEY (seq_region_id) REFERENCES seq_region(seq_region_id);
ALTER TABLE contig_info ADD FOREIGN KEY (author_id) REFERENCES author(author_id);

ALTER TABLE sequence_note ADD FOREIGN KEY (seq_region_id) REFERENCES seq_region(seq_region_id);
ALTER TABLE sequence_note ADD FOREIGN KEY (author_id) REFERENCES author(author_id);

ALTER TABLE author ADD FOREIGN KEY (group_id) REFERENCES author_group(group_id);

ALTER TABLE gene_name_update ADD FOREIGN KEY (gene_id) REFERENCES gene(gene_id);

# Why does this use contig_info, where (e.g.) seq_region_attrib does not?
ALTER TABLE contig_attrib ADD FOREIGN KEY (contig_info_id) REFERENCES contig_info(contig_info_id);
ALTER TABLE contig_attrib ADD FOREIGN KEY (attrib_type_id) REFERENCES attrib_type(attrib_type_id);

ALTER TABLE sequence_set_access ADD FOREIGN KEY (seq_region_id) REFERENCES seq_region(seq_region_id);
ALTER TABLE sequence_set_access ADD FOREIGN KEY (author_id) REFERENCES author(author_id);

ALTER TABLE evidence ADD FOREIGN KEY (transcript_id) REFERENCES transcript(transcript_id);

ALTER TABLE assembly_tagged_contig ADD FOREIGN KEY (seq_region_id) REFERENCES seq_region(seq_region_id);

ALTER TABLE transcript_author ADD FOREIGN KEY (transcript_id) REFERENCES transcript(transcript_id);
ALTER TABLE transcript_author ADD FOREIGN KEY (author_id) REFERENCES author(author_id);

ALTER TABLE gene_author ADD FOREIGN KEY (gene_id) REFERENCES gene(gene_id);
ALTER TABLE gene_author ADD FOREIGN KEY (author_id) REFERENCES author(author_id);


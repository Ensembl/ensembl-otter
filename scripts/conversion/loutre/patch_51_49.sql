-- Copyright [2018-2021] EMBL-European Bioinformatics Institute
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

#patch_51_50i.sql

#first patch was needed for gorilla but not mouse... pipeline db difference? Just comment out if it fails
ALTER TABLE meta DROP INDEX species_key_value_idx;

ALTER TABLE meta CHANGE COLUMN meta_value meta_value VARCHAR(255) NOT NULL;

#patch_51_50h.sql
ALTER TABLE external_db CHANGE COLUMN db_name db_name VARCHAR(28) NOT NULL;

#patch_51_50g.sql
ALTER TABLE `protein_feature` MODIFY COLUMN `score` DOUBLE NOT NULL;

#patch_51_50e.sql
ALTER TABLE protein_feature DROP COLUMN external_data;
ALTER TABLE dna_align_feature DROP COLUMN external_data;

#patch_51_50d.sql
ALTER TABLE meta DROP INDEX species_value_idx;
ALTER TABLE meta DROP COLUMN species_id;
ALTER TABLE coord_system DROP INDEX rank_idx;
ALTER TABLE coord_system DROP INDEX name_idx;
ALTER TABLE coord_system DROP INDEX species_idx;
ALTER TABLE coord_system DROP COLUMN species_id;

#patch_51_50c.sql
ALTER TABLE meta_coord DROP INDEX cs_table_name_idx;
ALTER TABLE meta_coord ADD UNIQUE INDEX `table_name` (`table_name`,`coord_system_id`);

#patch_51_50b.sql
ALTER TABLE protein_feature DROP INDEX hitname_idx;
ALTER TABLE protein_feature CHANGE COLUMN hit_name hit_id VARCHAR(40) NOT NULL;
ALTER TABLE protein_feature ADD INDEX hid_index (hit_id);

#patch_50_49e.sql
DROP TABLE seq_region_mapping;
DROP TABLE mapping_set;

#patch_50_49c.sql
ALTER TABLE gene CHANGE COLUMN canonical_transcript_id canonical_transcript INT(10) UNSIGNED default NULL;
ALTER TABLE gene DROP COLUMN canonical_annotation;

#patch_50_49b.sql
ALTER TABLE coord_system CHANGE COLUMN version version VARCHAR(40) DEFAULT NULL;

DELETE FROM meta where meta_key = 'patch' and meta_value like 'patch_50_51%';
DELETE FROM meta where meta_key = 'patch' and meta_value like 'patch_49_50%';
UPDATE meta SET meta_value='49' WHERE meta_key='schema_version';

ALTER TABLE meta ADD UNIQUE INDEX `key_value` (`meta_key`,`meta_value`);
ALTER TABLE meta ADD INDEX `meta_key_index` (`meta_key`);
ALTER TABLE meta ADD INDEX `meta_value_index` (`meta_value`);
ANALYZE TABLE meta;

ALTER TABLE coord_system ADD UNIQUE INDEX `rank` (`rank`);
ALTER TABLE coord_system ADD UNIQUE INDEX `name` (`name`,`version`);
ANALYZE TABLE coord_system;

ALTER TABLE seq_region DROP INDEX name_cs_idx;
ALTER TABLE seq_region DROP INDEX cs_idx;
ALTER TABLE seq_region ADD UNIQUE INDEX `coord_system_id` (`coord_system_id`,`name`);
ALTER TABLE seq_region ADD INDEX `name_idx` (`name`);
ANALYZE TABLE seq_region;

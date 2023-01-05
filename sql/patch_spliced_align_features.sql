-- Copyright [2018-2023] EMBL-European Bioinformatics Institute
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

########################################################################
# Tables for SplicedAlignFeatures
# based on {dna,protein}_align_feature

CREATE TABLE dna_spliced_align_feature (

  dna_spliced_align_feature_id  INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  seq_region_id                 INT(10) UNSIGNED NOT NULL,
  seq_region_start              INT(10) UNSIGNED NOT NULL,
  seq_region_end                INT(10) UNSIGNED NOT NULL,
  seq_region_strand             TINYINT(1) NOT NULL,
  hit_start                     INT NOT NULL,
  hit_end                       INT NOT NULL,
  hit_strand                    TINYINT(1) NOT NULL,
  hit_name                      VARCHAR(40) NOT NULL,
  analysis_id                   SMALLINT UNSIGNED NOT NULL,
  score                         DOUBLE,
  evalue                        DOUBLE,
  perc_ident                    FLOAT,
  alignment_type                ENUM('vulgar_exonerate_components'),
  alignment_string              TEXT,
  external_db_id                INTEGER UNSIGNED,
  hcoverage                     DOUBLE,
  external_data                 TEXT,

  PRIMARY KEY (dna_spliced_align_feature_id),
  KEY seq_region_idx (seq_region_id, analysis_id, seq_region_start, score),
  KEY seq_region_idx_2 (seq_region_id, seq_region_start),
  KEY hit_idx (hit_name),
  KEY analysis_idx (analysis_id),
  KEY external_db_idx (external_db_id)

) ENGINE=InnoDB;

CREATE TABLE protein_spliced_align_feature (

  protein_spliced_align_feature_id  INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  seq_region_id                     INT(10) UNSIGNED NOT NULL,
  seq_region_start                  INT(10) UNSIGNED NOT NULL,
  seq_region_end                    INT(10) UNSIGNED NOT NULL,
  seq_region_strand                 TINYINT(1) DEFAULT '1' NOT NULL,
  hit_start                         INT(10) NOT NULL,
  hit_end                           INT(10) NOT NULL,
  hit_name                          VARCHAR(40) NOT NULL,
  analysis_id                       SMALLINT UNSIGNED NOT NULL,
  score                             DOUBLE,
  evalue                            DOUBLE,
  perc_ident                        FLOAT,
  alignment_type                    ENUM('vulgar_exonerate_components'),
  alignment_string                  TEXT,
  external_db_id                    INTEGER UNSIGNED,
  hcoverage                         DOUBLE,

  PRIMARY KEY (protein_spliced_align_feature_id),
  KEY seq_region_idx (seq_region_id, analysis_id, seq_region_start, score),
  KEY seq_region_idx_2 (seq_region_id, seq_region_start),
  KEY hit_idx (hit_name),
  KEY analysis_idx (analysis_id),
  KEY external_db_idx (external_db_id)

) ENGINE=InnoDB;

# EOF

-- Copyright [2018] EMBL-European Bioinformatics Institute
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

insert into meta (meta_key,meta_value) values('last_gene_old_dbid',0);
insert into meta (meta_key,meta_value) values ('last_contig_info_old_dbid',0);

#################################################################################
#
# Table structure for table 'gene_stable_id_pool'
# otter table
# Used to create the stable_id sequence for API
#

CREATE TABLE gene_stable_id_pool (

   gene_pool_id     INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,

   PRIMARY KEY(gene_pool_id)

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'gene_author'
# otter table
#

CREATE TABLE gene_author (

   gene_id      INT(10) UNSIGNED NOT NULL REFERENCES gene(gene_id),
   author_id  INT(10) UNSIGNED DEFAULT '0' NOT NULL REFERENCES author(author_id),

   PRIMARY KEY ( gene_id ),
   KEY ( author_id )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'transcript_stable_id_pool'
# otter table
# Used to create the stable_id sequence for API
#

CREATE TABLE transcript_stable_id_pool (

   transcript_pool_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,

   PRIMARY KEY ( transcript_pool_id )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'transcript_author'
# otter table
#

CREATE TABLE transcript_author (

   transcript_id         INT UNSIGNED NOT NULL REFERENCES transcript(transcript_id),
   author_id             INT(10) UNSIGNED NOT NULL REFERENCES author(author_id),

   PRIMARY KEY (transcript_id),
   KEY (author_id)

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'evidence'
# otter table
# one transcript version -> 0 or many evidences
#

CREATE TABLE evidence (

   transcript_id        INT UNSIGNED NOT NULL REFERENCES transcript(transcript_id),
   name                VARCHAR(40) NOT NULL,
   type                ENUM('EST','ncRNA','cDNA','Protein','Genomic','SRA','UNKNOWN'),

   PRIMARY KEY ( transcript_id,name,type )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'translation_stable_id_pool'
# otter table
# Used to create the stable_id sequence for API
#

CREATE TABLE translation_stable_id_pool (

  translation_pool_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,

  PRIMARY KEY ( translation_pool_id )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'exon_stable_id_pool'
# otter table
# Used to create the stable_id sequence for API
#

CREATE TABLE exon_stable_id_pool (

  exon_pool_id INT UNSIGNED NOT NULL AUTO_INCREMENT,

  PRIMARY KEY ( exon_pool_id )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'author'
# otter table
# Used to store annotation author s personal details
#

CREATE TABLE author (

  author_id        INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  author_email        VARCHAR(50) NOT NULL,
  author_name        VARCHAR(50) NOT NULL,
  group_id          int(10) not null references author_group(group_id),

  PRIMARY KEY ( author_id ),
  UNIQUE (author_name,author_email),
  UNIQUE ( author_email,group_id )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'author_group'
# otter table
# Used to store the group details of each of the author of the author table
#

CREATE TABLE author_group (

   group_id     INT NOT NULL AUTO_INCREMENT,
   group_name     VARCHAR(100) NOT NULL default '',
   group_email VARCHAR(50),

   PRIMARY KEY ( group_id ),
   UNIQUE gn_idx ( group_name )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'contig_info'
# otter table
# annotated contig versions
#

CREATE TABLE contig_info (

  contig_info_id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  seq_region_id        INT(10) UNSIGNED NOT NULL REFERENCES seq_region_id(seq_region),
  author_id        INT(10) UNSIGNED NOT NULL REFERENCES author(author_id),
  created_date        DATETIME DEFAULT '0000-00-00 00:00:00' NOT NULL,
  is_current         BOOLEAN DEFAULT 1 NOT NULL,

  PRIMARY KEY ( contig_info_id )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'contig_attrib'
# otter table
# 1 contig version -> 0 or many attribs
# (remark,hidden_remark,keyword,description,annotated)
#

CREATE TABLE contig_attrib (

   contig_info_id    INT(10) UNSIGNED NOT NULL DEFAULT '0' REFERENCES contig_info(contig_info_id),
   attrib_type_id    SMALLINT(5) UNSIGNED NOT NULL DEFAULT '0' REFERENCES attrib_type(attrib_type_id),
   value         TEXT NOT NULL,

   KEY ( contig_info_id,attrib_type_id )

) ENGINE=InnoDB;

################################################################################
#
# Table structure for table 'contig_lock'
# otter table
# locks for a set of seq_region_id/s per annotator in a transaction
#

CREATE TABLE contig_lock (

  contig_lock_id    INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  seq_region_id        INT(10) UNSIGNED NOT NULL REFERENCES seq_region(seq_region_id),
  author_id        INT(10)    DEFAULT '0' NOT NULL REFERENCES author(author_id),
  hostname        VARCHAR(100) NOT NULL,
  timestamp        DATETIME DEFAULT '0000-00-00 00:00:00' NOT NULL,

  PRIMARY KEY ( contig_lock_id ),
  UNIQUE KEY seq_region_id (seq_region_id)

) ENGINE=InnoDB;

#################################################################################
# Table structure for table 'assembly_tag'
# otter table
#

CREATE TABLE assembly_tag (

  tag_id          INT(10) UNSIGNED NOT NULL auto_increment,
  seq_region_id          INT(10) UNSIGNED NOT NULL default '0' REFERENCES seq_region(seq_region_id),
  seq_region_start        INT(10) NOT NULL,
  seq_region_end          INT(10) NOT NULL,
  seq_region_strand       tinyint(1) NOT NULL,
  tag_type          ENUM('Unsure','Clone_left_end','Clone_right_end','Misc') NOT NULL DEFAULT 'Misc',
  tag_info          TEXT,

  PRIMARY KEY  ( tag_id ),
  UNIQUE ( seq_region_id, seq_region_start, seq_region_end, seq_region_strand, tag_type, tag_info(250))
) ENGINE=InnoDB ;


#################################################################################
# Table structure for table 'assembly_tagged_clone'
# otter table
#

CREATE TABLE assembly_tagged_contig (

  seq_region_id int(10) unsigned NOT NULL default '0',
  transferred enum('yes','no') NOT NULL default 'no',

  UNIQUE KEY seq_region_id (seq_region_id)

) ENGINE=InnoDB ;


#################################################################################
# Table structure for table 'sequence_note'
# otter table
#

CREATE TABLE sequence_note (

  seq_region_id           INT(10) UNSIGNED NOT NULL default '0' REFERENCES seq_region(seq_region_id),
  author_id           INT(10) UNSIGNED NOT NULL default '0' REFERENCES author(author_id),
  note_time           DATETIME NOT NULL DEFAULT '0000-00-00 00:00:00',
  is_current           ENUM('yes','no') NOT NULL default 'no',
  note               TEXT,

  PRIMARY KEY  ( seq_region_id,author_id,note_time ),
  KEY ( seq_region_id,is_current )

) ENGINE=InnoDB ;



#################################################################################
# Table structure for table 'sequence_set_access'
# otter table
#

CREATE TABLE sequence_set_access (

  seq_region_id int unsigned NOT NULL default '0',
  author_id int(10) unsigned NOT NULL default '0',
  access_type enum('','R','RW') NOT NULL default 'R',

  PRIMARY KEY  (`seq_region_id`,`author_id`)

) ENGINE=InnoDB;
##################################################################################

# all attributes in *_attrib tables are defined first in the file
# ensembl/misc-scripts/attribute_types/attrib_type.txt
# gene_attrib (remark,name,synonym)
# transcript_attrib (mRNA_start_NF,mRNA_end_NF,cds_start_NF,cds_end_NF,remark,name)
# seq_region_attrib (chr,description,htgs_phase,intl_clone_name,embl_accession,embl_version)
#

##################################################################################
# Database Schema for Otter Annotation Database Version 37.0
# based on Ensembl Database Schema Version 37.0
#
# Sindhu K. Pillai <sp1@sanger.ac.uk>
################################################################################

# SQL for otter - manual annotation database

create table assembly_tag (
       tag_id		    INT(10)    UNSIGNED NOT NULL AUTO_INCREMENT,
       contig_id	    INT(10)    UNSIGNED NOT NULL,
       contig_start	    INT(10)    NOT NULL,
       contig_end	    INT(10)    NULL,
       contig_strand	    TINYINT(1) NOT NULL DEFAULT '0',
       tag_type		    ENUM('Unsure', 'Clone_left_end', 'Clone_right_end', 'Misc') NOT NULL DEFAULT 'Misc',
       tag_info		    TEXT       NULL, 		    

       PRIMARY KEY (tag_id),
       UNIQUE KEY (contig_id, contig_start, contig_end, contig_strand, tag_type)
);

create table assembly_tagged_clone (
       clone_id		   INT(10)        UNSIGNED NOT NULL,
       transferred	   ENUM('yes', 'no') NOT NULL DEFAULT 'no',

       UNIQUE KEY (clone_id)
);

CREATE TABLE `author` (
  `author_id` int(10) unsigned NOT NULL auto_increment,
  `author_email` varchar(50) default NULL,
  `author_name` varchar(50) default NULL,
  `group_id` int(10) unsigned default NULL,
  PRIMARY KEY  (`author_id`),
  UNIQUE KEY `author_name` (`author_name`)
);


CREATE TABLE `author_group` (
  `group_id` int(10) unsigned NOT NULL auto_increment,
  `group_email` varchar(50) default NULL,
  `group_name` varchar(50) default NULL,
  PRIMARY KEY  (`group_id`),
  UNIQUE KEY `group_name` (`group_name`)
);

create table keyword (
	keyword_id  int(10) unsigned NOT NULL auto_increment,
        keyword_name  varchar(50),
        PRIMARY KEY (keyword_id)
);

create table clone_info_keyword (
	keyword_id  int(10) unsigned DEFAULT '0' NOT NULL,
	clone_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (keyword_id,clone_info_id),
	KEY clone_info_id_idx (clone_info_id)
);

create table clone_remark (
	clone_remark_id int(10) unsigned NOT NULL auto_increment,
	remark TEXT,
	clone_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (clone_remark_id),
        
        KEY(clone_info_id, clone_remark_id)
);

create table clone_info (
	clone_info_id int(10) unsigned NOT NULL auto_increment,
        clone_id int(10) unsigned default '0' not null,
	author_id int(10),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,

        PRIMARY KEY (clone_info_id) 
);

create table clone_lock (
	clone_lock_id int(10) unsigned NOT NULL auto_increment,
	clone_id int(10) unsigned default '0' not null,
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
	author_id int(10) DEFAULT '0' NOT NULL,
        hostname varchar(80),
        
        PRIMARY KEY (clone_lock_id),
        UNIQUE INDEX clone_index (clone_id)
);

create table gene_name (
	gene_name_id int(10) unsigned NOT NULL auto_increment,
	name varchar(100),
	gene_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (gene_name_id),
        KEY (name),
	KEY (gene_info_id)
);

create table gene_synonym (
	synonym_id int(10) unsigned NOT NULL auto_increment,
	name varchar(100),
	gene_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (synonym_id),
	KEY gene_info_id (gene_info_id)
);

create table gene_remark (
	gene_remark_id int(10) unsigned NOT NULL auto_increment,
	remark TEXT, 
	gene_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (gene_remark_id),
	KEY (gene_info_id)
);

create table gene_info (
	gene_info_id int(10) unsigned NOT NULL auto_increment,
	gene_stable_id varchar(40),
	author_id int(10) unsigned DEFAULT '0' NOT NULL,
        is_known enum('true', 'false') not null default 'false',
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        KEY gene_stable_id (gene_stable_id),
        PRIMARY KEY (gene_info_id)
);

create table transcript_remark (
	transcript_remark_id int(10) unsigned NOT NULL auto_increment,
	remark TEXT,
	transcript_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (transcript_remark_id),
	KEY (transcript_info_id)
);

create table transcript_class (
	transcript_class_id int(10) unsigned NOT NULL auto_increment,
	name varchar(40) unique,
	description varchar(255),
        PRIMARY KEY (transcript_class_id)
);

create table transcript_info (
	transcript_info_id int(10) unsigned NOT NULL auto_increment,
	transcript_stable_id varchar(40),
	name varchar(40),
	transcript_class_id int(10) unsigned,
	cds_start_not_found enum('true','false') not null,
	cds_end_not_found enum('true','false') not null,
	mRNA_start_not_found enum('true','false') not null,
	mRNA_end_not_found enum('true','false') not null,
	author_id int(10) unsigned default '0' not null,
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,

        PRIMARY KEY (transcript_info_id)
	);

create table transcript_synonym (
        transcript_name varchar(40) not null,
        transcript_synonym varchar(40) not null,
        
        PRIMARY KEY (transcript_name, transcript_synonym)
        );

create table exon_synonym (
        exon_name varchar(40) not null,
        exon_synonym varchar(40) not null,
        
        PRIMARY KEY (exon_name, exon_synonym)
        );

create table evidence (
	evidence_id int(10) unsigned not null auto_increment,
	evidence_name varchar(40),
	transcript_info_id  int(10) unsigned,
	type enum('EST','cDNA','Protein','Genomic','UNKNOWN'),
        PRIMARY KEY (evidence_id),
        KEY (transcript_info_id, evidence_name, type)
	);

create table current_clone_info (
        clone_id      int(10) unsigned default '0' not null,
        clone_info_id int(10) unsigned default '0' not null,
        PRIMARY KEY (clone_id)   
        );

create table current_gene_info (
	gene_info_id int(10) unsigned default '0' not null,
	gene_stable_id varchar(40),
	PRIMARY KEY (gene_info_id),
	KEY (gene_stable_id)
	);

create table current_transcript_info (
	transcript_info_id int(10) unsigned default '0' not null,
	transcript_stable_id varchar(40),
	PRIMARY KEY (transcript_info_id),
	KEY (transcript_stable_id)
	);

create table gene_stable_id_pool (
        gene_pool_id  int(10) unsigned not null auto_increment,
        gene_stable_id varchar(40),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (gene_pool_id),
        KEY (gene_stable_id)
        );

create table transcript_stable_id_pool (
        transcript_pool_id  int(10) unsigned not null auto_increment,
        transcript_stable_id varchar(40),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (transcript_pool_id),
        KEY (transcript_stable_id)
        );

create table translation_stable_id_pool (
        translation_pool_id  int(10) unsigned not null auto_increment,
        translation_stable_id varchar(40),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (translation_pool_id),
        KEY (translation_stable_id)
        );

create table exon_stable_id_pool (  
        exon_pool_id  int(10) unsigned not null auto_increment,
        exon_stable_id varchar(40),
        timestamp datetime DEFAULT '0000-00-,00 00:00:00' NOT NULL,
        PRIMARY KEY (exon_pool_id),
        KEY (exon_stable_id)
        );
        
# Table structure for table 'hit_description'
# Table for the Finished Analysis Runnables to store hit information in.
# hit_name         joins to hit_name of dna_align_feature & protein_align_feature tables
# hit_length       sequence length.
# hit_description  DE line from EMBL/TrEMBL/Swissprot format file
# hit_taxon        Taxon ID for sequence
# hit_db column open to change
#

CREATE TABLE hit_description (
  hit_name varchar(40) DEFAULT '' NOT NULL,
  hit_length int(10) unsigned,
  hit_description text,
  hit_taxon int(10) unsigned,
  hit_db enum('EMBL','Swissprot','TrEMBL','Pfam') DEFAULT 'EMBL' NOT NULL,
  PRIMARY KEY (hit_name),
  KEY hit_db (hit_db)
);

# To change from previous version [patch] does not affect column values.
#ALTER TABLE hit_description MODIFY hit_db ENUM('EMBL','Swissprot','TrEMBL','Pfam') DEFAULT 'EMBL' NOT NULL;


#################################################
# Extra tables used by Sanger otter/lace system
#################################################

# sequence set table for pipeline and otter databases 

create table sequence_set (
    assembly_type varchar (20) NOT NULL,
    description TEXT,
    analysis_priority int,
    hide ENUM ('Y', 'N') DEFAULT 'N' NOT NULL,
    vega_set_id int(10) unsigned DEFAULT '0' NOT NULL,
    PRIMARY KEY(assembly_type)
    );

create table vega_set (
    vega_set_id int(10) unsigned NOT NULL auto_increment,
    vega_author_id int(10) unsigned DEFAULT '0' NOT NULL,
    vega_type ENUM ('E', 'I', 'N', 'P') DEFAULT 'N' NOT NULL,
    vega_name varchar (20),
    PRIMARY KEY(vega_set_id),
    UNIQUE (vega_name)
    );

create table vega_author (
    vega_author_id  int(10) unsigned NOT NULL auto_increment,
    author_email varchar(50),
    author_name  varchar(50),
    PRIMARY KEY (vega_author_id),
    UNIQUE (author_name)
);

create table sequence_note (
    contig_id   INT (10) unsigned DEFAULT '0' NOT NULL,
    author_id   INT (10) unsigned DEFAULT '0' NOT NULL,
    is_current  ENUM ('Y', 'N') DEFAULT 'N' NOT NULL,
    note_time   DATETIME NOT NULL,
    note        TEXT,
    
    KEY(contig_id, is_current),
    PRIMARY KEY(contig_id, author_id, note_time)
);

create table sequence_set_access (
    assembly_type varchar (20) NOT NULL,
    author_id INT(10) unsigned DEFAULT '0' NOT NULL,
    access_type ENUM('R', 'RW') DEFAULT 'R' NOT NULL,
    
    PRIMARY KEY(assembly_type, author_id)
);

create table contig_annotation_status (
    conitg_ann_status_id  INT(10) unsigned NOT NULL  auto_increment,
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    author_id INT(10) unsigned DEFAULT '0' NOT NULL,
    status_date DATETIME,
    status ENUM(
        'in_progress',
        'annotated',
        'marked_for_checking',
        'checked',
        'marked_for_submission',
        'submitted'
        ),
    
    PRIMARY KEY (conitg_ann_status_id),
    KEY cln_stat_date (contig_id, status, status_date)
);

create table current_contig_annotation_status (
    conitg_ann_status_id  INT(10) unsigned DEFAULT '0' NOT NULL,
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    
    PRIMARY KEY (conitg_ann_status_id),
    KEY (contig_id)
);


# Private contigs do not get copied to the external VEGA site.
# This should be part of the contig table, but is not part of the core schema
# Maybe: alter table contig add column is_private ENUM('Y', 'N') DEFAULT 'N';

create table private_contig (
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    
    PRIMARY KEY(contig_id)
);

create table vega_snap (
    vega_snap_id    INT(10) unsigned NOT NULL auto_increment,
    vega_snap_date  DATETIME,
    author_id       INT(10) unsigned DEFAULT '0' NOT NULL,
    
    primary key (vega_snap_id),
    key (vega_snap_date)
);

create table vega_set_snap (
    vega_snap_id    INT(10) unsigned DEFAULT '0' NOT NULL,
    set_snap_id     INT(10) unsigned DEFAULT '0' NOT NULL,
    
    primary key (vega_snap_id, set_snap_id)
);

create table set_snap (
    set_snap_id     INT(10) unsigned NOT NULL auto_increment,
    set_snap_date   DATETIME,
    author_id       INT(10) unsigned DEFAULT '0' NOT NULL,
    is_current      ENUM('Y', 'N') DEFAULT 'N' NOT NULL,
    
    primary key (set_snap_id),
    key (set_snap_date)
);

create table set_snap_gene (
    set_snap_id     INT(10) unsigned DEFAULT '0' NOT NULL,
    gene_id         INT(10) unsigned DEFAULT '0' NOT NULL,
    
    primary key (set_snap_id, gene_id)
);

create table set_snap_clone_info (
    set_snap_id     INT(10) unsigned DEFAULT '0' NOT NULL,
    clone_info_id   INT(10) unsigned DEFAULT '0' NOT NULL,
    
    primary key (set_snap_id, clone_info_id)
);


####################################################################
#        ALTER TABLE (for tables in ensembl or ensembl-pipeline)
####################################################################
                                                                                                                                                          
ALTER TABLE repeat_consensus add key `consensus` (`repeat_consensus`(10));


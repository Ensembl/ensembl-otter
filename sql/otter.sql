# SQL for otter - manual annotation database

create table author (
	author_id  int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	author_email varchar(50),
        author_name  varchar(50),
        PRIMARY KEY (author_id)
);
create table keyword (
	keyword_id  int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
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
	clone_remark_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	remark TEXT,
	clone_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (clone_remark_id)
);

create table clone_info (
	clone_info_id int(10) unsigned DEFAULT '0' NOT NULL  auto_increment,
        clone_id int(10) unsigned default '0' not null,
	author_id int(10),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
	is_active enum('true','false'),
	embl_description varchar(255),
	database_source varchar(255),
        PRIMARY KEY (clone_info_id) 
);

create table clone_lock (
	clone_lock_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	clone_id varchar(40) NOT NULL,
	clone_version int(10) unsigned DEFAULT '0' NOT NULL,
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
	author_id int(10) DEFAULT '0' NOT NULL,
        PRIMARY KEY (clone_lock_id),
        UNIQUE INDEX clone_index (clone_id,clone_version)
);

create table gene_name (
	gene_name_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	name varchar(100),
	gene_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (gene_name_id)
);

create table gene_synonym (
	synonym_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	name varchar(100),
	gene_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (synonym_id)
);

create table gene_remark (
	gene_remark_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	remark VARCHAR(255), 
	gene_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (gene_remark_id)
);

create table gene_info (
	gene_info_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	gene_stable_id varchar(40),
	author_id int(10) unsigned DEFAULT '0' NOT NULL,
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (gene_info_id)
);

create table transcript_remark (
	transcript_remark_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	remark varchar(255),
	transcript_info_id int(10) unsigned DEFAULT '0' NOT NULL,
        PRIMARY KEY (transcript_remark_id)
);

create table transcript_class (
	transcript_class_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
	name varchar(40) unique,
	description varchar(255),
        PRIMARY KEY (transcript_class_id)
);

create table transcript_info (
	transcript_info_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
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

create table evidence (
	evidence_id int(10) unsigned default '0' not null auto_increment,
	evidence_name varchar(40),
	transcript_info_id  int(10) unsigned,
	type enum('EST','cDNA','Protein','Genomic'),
        PRIMARY KEY (evidence_id)
	);

create table current_clone_info (
        clone_info_id int(10) unsigned default '0' not null,
        clone_id   varchar(40),   
        clone_version int(10),   
        PRIMARY KEY (clone_info_id)   
        );


create table current_gene_info (
	gene_info_id int(10) unsigned default '0' not null,
	gene_stable_id varchar(40),
	PRIMARY KEY (gene_info_id)
	);

create table current_transcript_info (
	transcript_info_id int(10) unsigned default '0' not null,
	transcript_stable_id varchar(40),
	PRIMARY KEY (transcript_info_id)
	);
create table gene_stable_id_pool (
        gene_pool_id  int(10) unsigned default '0' not null auto_increment,
        gene_stable_id varchar(40),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (gene_pool_id)
        );

create table transcript_stable_id_pool (
        transcript_pool_id  int(10) unsigned default '0' not null auto_increment,
        transcript_stable_id varchar(40),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (transcript_pool_id)
        );

create table translation_stable_id_pool (
        translation_pool_id  int(10) unsigned default '0' not null auto_increment,
        translation_stable_id varchar(40),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (translation_pool_id)
        );

create table exon_stable_id_pool (  
        exon_pool_id  int(10) unsigned default '0' not null auto_increment,
        exon_stable_id varchar(40),
        timestamp datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
        PRIMARY KEY (exon_pool_id)
        );

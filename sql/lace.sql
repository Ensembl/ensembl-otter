
# Extra tables used by Sanger otter/lace system

# sequence set table for pipeline and otter databses 

create table sequence_set (
    assembly_type varchar (20) NOT NULL,
    description TEXT,
    analysis_priority int,
    
    PRIMARY KEY(assembly_type)
    );

create table sequence_note (
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    author_id INT(10) unsigned DEFAULT '0' NOT NULL,
    is_current ENUM('Y','N') DEFAULT 'N',
    note_time DATETIME,
    note TEXT,
    
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
    conitg_ann_status_id  INT(10) unsigned DEFAULT '0' NOT NULL  auto_increment,
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


# This should be part of the contig table, but is not part of the core schema
# Maybe: alter table contig add column is_private ENUM('Y', 'N') DEFAULT 'N';

create table private_contig {
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    
    PRIMARY KEY(contig_id)
}

create table contig_vega_status (
    contig_vega_status_id  INT(10) unsigned DEFAULT '0' NOT NULL  auto_increment,
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    author_id INT(10) unsigned DEFAULT '0' NOT NULL,
    vega_status_date DATETIME,
    vega_status ENUM(
        'unpublished',
        'marked_for_publication',
        'published'
        ),
    
    PRIMARY KEY (contig_vega_status_id),
    KEY cln_stat_date (contig_id, vega_status, status_date)
);

create table current_contig_vega_status (
    contig_vega_status_id  INT(10) unsigned DEFAULT '0' NOT NULL,
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    
    PRIMARY KEY (contig_status_id),
    KEY (contig_id)
);

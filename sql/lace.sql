
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

create table contig_status (
    contig_status_id  INT(10) unsigned DEFAULT '0' NOT NULL  auto_increment,
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    author_id INT(10) unsigned DEFAULT '0' NOT NULL,
    status_date DATETIME,
    status ENUM(
        'annotated',
        'marked_for_checking',
        'checked',
        'marked_for_submitting',
        'submitted'
        ),
    
    PRIMARY KEY (contig_status_id),
    KEY cln_stat_date (contig_id, status, status_date)
);

create table current_contig_status (
    contig_status_id  INT(10) unsigned DEFAULT '0' NOT NULL,
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    
    PRIMARY KEY (contig_status_id),
    KEY (contig_id)
);

create table contig_vega_status (
    contig_vega_status_id  INT(10) unsigned DEFAULT '0' NOT NULL  auto_increment,
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    author_id INT(10) unsigned DEFAULT '0' NOT NULL,
    vega_status_date DATETIME,
    vega_status ENUM(
        'unpublished',
        'private',
        'marked_for_publishing',
        'vega_published'
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

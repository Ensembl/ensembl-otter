
# Extra tables used by Sanger otter/lace system

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
    vega_set_id int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
    vega_author_id int(10) unsigned DEFAULT '0' NOT NULL,
    vega_type ENUM ('E', 'I', 'N', 'P') DEFAULT 'N' NOT NULL,
    vega_name varchar (20),
    PRIMARY KEY(vega_set_id),
    UNIQUE (vega_name)
    );

create table vega_author (
    vega_author_id  int(10) unsigned DEFAULT '0' NOT NULL auto_increment,
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


# Private contigs do not get copied to the external VEGA site.
# This should be part of the contig table, but is not part of the core schema
# Maybe: alter table contig add column is_private ENUM('Y', 'N') DEFAULT 'N';

create table private_contig (
    contig_id INT(10) unsigned DEFAULT '0' NOT NULL,
    
    PRIMARY KEY(contig_id)
);

create table vega_snap (
    vega_snap_id    INT(10) unsigned DEFAULT '0' NOT NULL  auto_increment,
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
    set_snap_id     INT(10) unsigned DEFAULT '0' NOT NULL  auto_increment,
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

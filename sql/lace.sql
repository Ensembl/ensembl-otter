
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

package Bio::Otter::QueryUser;

use vars qw(@ISA);
use strict;

use OtterDefs;
use Bio::EnsEMBL::Root;
use Bio::EnsEMBL::Clone;
use Bio::EnsEMBL::RawContig;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

@ISA = qw(Bio::EnsEMBL::DBSQL::DBAdaptor);


sub new {
  my($class,@args) = @_;

  my $self = $class->SUPER::new(@args);

  return $self;
}

sub create_database {
    my ($self,$db) = @_;

    print "\nCreating database $db on host " . $self->host . " port " . $self->port . "\n\n";

    my @databases = @{$self->get_databases};

    my $found = 0;

    foreach my $tmpdb(@databases) {
	if ($tmpdb eq $db) {
	    $found = 1;
	    last;
	}
    }

    if ($found == 1) {
	print "Database $db already exists\n";
	return;
    }

    my $query = "create database $db";

    my $sth = $self->db_handle->prepare($query);

    my $res = $sth->execute;

    my $ensembl_sql = '/Users/michele/cvs/ensembl-otter/sql/table_transact.sql';
    my $otter_sql   = '/Users/michele/cvs/ensembl-otter/sql/otter_transact.sql';

    my $newdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $self->host,
						 -user => $self->username,
						 -pass => $self->password,
						 -port => $self->port,
						 -dbname => $db);

    $self->load_sql_file($newdb,($ensembl_sql,$otter_sql));

    return $newdb;
}

sub delete_database {
    my ($self,$db) = @_;

    print "\nPreparing to delete database $db on host " . $self->host . " port " . $self->port . "\n";

    my @databases = @{$self->get_databases};

    my $found = 0;

    foreach my $tmpdb(@databases) {
	if ($tmpdb eq $db) {
	    $found = 1;
	    last;
	}
    }

    if ($found == 0) {
	print "Database $db doesn't exist\n";
	return;
    }

    print "\nAre you sure you want to delete database $db on host " . $self->host . " port " . $self->port . " y/n : ";

    my $choice;

    while ($choice = <>) {
	chomp($choice);

	if ($choice eq "Y" ||
	    $choice eq "N" ||
	    $choice eq "y" ||
	    $choice eq "n")  {
	    
	    $choice =~ tr/yn/YN/;
	    
	    last;
	}
    }

    if ($choice eq "N") {
	print "\nAbandoning delete for database\n";
	return;
    } else {
	my $query = "drop database $db";

	my $sth = $self->db_handle->prepare($query);
	my $res = $sth->execute;

	print "\nDatabase $db deleted\n";
    }
}
sub create_assembly {
    my ($self,$db,$def) = @_;

    print "\nPreparing to create an assembly for database " . $db->dbname . " on host " . $db->host . " port " . $db->port . "\n";


    print "\nEnter the assembly name you wish to use : ";

    my $choice = <>;

    chomp($choice);

    print "\nAssembly name chosen is $choice\n";

    return $choice;
}

sub store_sequences {
    my ($self,$db,@seqs) = @_;

    my $start = 1;
    my $gap   = 5000;
    my $type = $db->assembly_type;

    my $chrobj;

    eval {
	$chrobj = $db->get_ChromosomeAdaptor->fetch_by_chr_name($type);
    };

    my $chrid;

    my $sth = $db->prepare("insert into meta values(null,'assembly.default','$type')");
    my $res = $sth->execute;

    if (!defined($chrobj)) {
	print "\nStoring chromosome $type\n";
	
	my $chrsql = "insert into chromosome(chromosome_id,name) values(null,'$type')";
	my $sth    = $db->prepare($chrsql);
	my $res    = $sth->execute;

	$sth = $db->prepare("SELECT last_insert_id()");
	$sth->execute;
	
	($chrid) = $sth->fetchrow_array;
	$sth->finish;
    } else {
	print "Using existing chromosome " . $chrobj->dbID . "\n";
	$chrid = $chrobj->dbID;
    }

    my $time  = time;
    my $start = 1;

    foreach my $tmpseq (@seqs) { 
	print "Storing " . $tmpseq->id . "\n";
	my $id = $tmpseq->id; 
	my $version = 1; 

	if ($tmpseq->id =~ /(\S+)\.(\S+)/) { 
	    $id      = $1; 
	    $version = $2; 
	} 
	
	# Should check the clone and contig don't already exist

	# Create clone

	my $clone = new Bio::EnsEMBL::Clone();
	$clone->id($id);
	$clone->embl_id($id);
	$clone->version(1);
	$clone->embl_version($version);
	$clone->htg_phase(-1);
	$clone->created($time);
	$clone->modified($time);

	# Create contig

	my $contig = new Bio::EnsEMBL::RawContig;
	
	$contig->name("$id.$version.1.".length($tmpseq->seq));
	$contig->clone($clone);
	$contig->embl_offset(1);
	$contig->length($tmpseq->length);
	$contig->seq($tmpseq->seq);

	$clone->add_Contig($contig);

	$db->get_CloneAdaptor->store($clone);

	# Make an entry in the assembly table
	
	my $offset  = 1;
	my $raw_end = $tmpseq->length;
	my $end     = $start + $tmpseq->length - 1;
	my $id      = $contig->id;
	my $length  = $tmpseq->length;
	my $rawid   = $contig->dbID;

	my $sqlstr = "insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values($chrid,$start,$end,\'$id\',1,$length,1,$rawid,$offset,$raw_end,1,\'$type\')\n";
	
	print "SQL $sqlstr\n";

	my $sth = $db->prepare($sqlstr);
	my $res = $sth->execute;

	$start += $tmpseq->length + $gap;
    }
}
    
sub load_sql_file {
    my( $self, $dbh,@files ) = @_;

    local *SQL;

    my $i = 0; 

    my $comment_strip_warned=0;
        
    foreach my $file (@files) {
	print "Loading sql file $file\n";
        my $sql = '';
        open SQL, $file or die "Can't read SQL file '$file' : $!";
	
        while (<SQL>) {
            # careful with stripping out comments; quoted text
            # (e.g. aligments) may contain them. Just warn (once) and ignore
            if (    /'[^']*#[^']*'/
		|| /'[^']*--[^']*'/ ) {
		    if ( $comment_strip_warned++ ) {
			# already warned
		    } else {
			warn "#################################\n".
			warn "# found comment strings inside quoted string; not stripping, too complicated: $_\n";
			warn "# (continuing, assuming all these they are simply valid quoted strings)\n";
			warn "#################################\n";
		    }
		} else {
                s/(#|--).*//;       # Remove comments
            }
            next unless /\S/;   # Skip lines which are all space
            $sql .= $_;
            $sql .= ' ';
	    }
        close SQL;
	
        #Modified split statement, only semicolumns before end of line,
        #so we can have them inside a string in the statement
        #\s*\n, takes in account the case when there is space before the new line
        foreach my $s (grep /\S/, split /;[ \t]*\n/, $sql) {
            $s =~ s/\;\s*$//g;
            my $sth = $dbh->prepare($s);
	    my $res = $sth->execute;
            $i++
	    }
    }
    return $i;
}                                       # do_sql_file


    
	
sub get_databases {
    my ($self) = @_;

    my $query = "show databases";

    my $sth = $self->db_handle->prepare($query);

    my $res = $sth->execute;

    my @databases;

    while (my $ref = $sth->fetchrow_arrayref) {
	push(@databases,$ref->[0]);
    }
    
    return \@databases;
}

sub get_ensembl_databases {
    my ($self) = @_;
    
    my @databases = @{$self->get_databases};
    my @newdbs;

    my %ensembl_tables;

    $ensembl_tables{'assembly'}   = 1;
    $ensembl_tables{'clone'}      = 1;
    $ensembl_tables{'contig'}     = 1;
    $ensembl_tables{'chromosome'} = 1;

    
    foreach my $db (@databases) {

	eval {
	    my $newdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $self->host,
							   -user => $self->username,
							   -port => $self->port,
							   -pass => $self->password,
							   -dbname => $db);
	    
	    
	    my @tables = @{$self->get_tables($newdb)};
	    
	    my %tablehash;
	    
	    foreach my $table (@tables) {
		$tablehash{$table} = 1;
	    }
	    
	    my $found = 1;
	    
	    foreach my $tab (keys %ensembl_tables) {

		if ($tablehash{$tab} != 1) {
		    $found = 0;
		    last;
		}
	    }
	    
	    if ($found == 1) {
		push(@newdbs,$db);
	    }
	};
	if ($@) {
	    print STDERR "Couldn't connect to database $db\n";
	    
	}
    }
    
    return \@newdbs;
}
	
sub get_tables {
    my ($self,$db) = @_;

    my $newdb = $db;

    my @tables;

    if (!$db->isa("Bio::EnsEMBL::DBSQL::DBConnection")) {
	$newdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $self->host,
						    -user => $self->username,
						    -port => $self->port,
						    -pass => $self->password,
						    -dbname => $db);
    } 

    my $query = "show tables";

    my $sth = $newdb->prepare($query);

    my $res = $sth->execute;

    while (my $ref = $sth->fetchrow_arrayref) {
	push(@tables,$ref->[0]);
    }

    return \@tables;
}

	

sub get_assemblies {
    my ($self,$database) = @_;

    my $newdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $self->host,
						   -user => $self->username,
						   -port => $self->port,
						   -pass => $self->password,
						   -dbname => $database);

    my $query = "select distinct type from assembly";

    my $sth = $newdb->prepare($query);

    my $res = $sth->execute;

    my @assemblies;

    while (my $ref = $sth->fetchrow_arrayref) {
	push(@assemblies,$ref->[0]);
    }

    return \@assemblies;
}

sub query_for_database {
    my ($self) = @_;

    my @databases = @{$self->get_ensembl_databases};

    print "\nDo you want to create a new database y/n : ";

    my $choice;

    while ($choice = <>) {
	chomp($choice);

	if ($choice eq "Y" ||
	    $choice eq "N" ||
	    $choice eq "y" ||
	    $choice eq "n")  {
	    
	    $choice =~ tr/yn/YN/;
	    
	    last;
	}
    }

    if ($choice eq "N") {
	print "\nEnsembl databases available on host " . $self->host . " port [" . $self->port . "] are :\n\n";
	
	my $count = 1;
	
	foreach my $db (@databases) {
	    printf ("%5d %s\n",$count, $db);
	    $count++;
	}
	
	print "\n";
	
	print "Please select the number of the database to insert into : ";
	
	my $num;
	
	while ($num = <>) {
	    chomp($num);
	    if ($num >= 1 &&  $num <= scalar(@databases)) {
		last;
	    }
	}
	
	my $db = $databases[$num-1];
	
	return $db;

    } else {

	print "\nEnter the name of the database to create : ";

	my $dbname = <>;

	chomp($dbname);

	my $newdb = $self->create_database($dbname);
	
	return $dbname;
    }

}

sub query_for_assembly {
    my ($self,$db) = @_;

    my @assemblies = @{$self->get_assemblies($db)};

    print "\nAssemblies available on host " . $self->host . " database $db are :\n\n";

    my $count = 1;

    foreach my $ass (@assemblies) {
	printf ("%5d %s\n",$count, $ass);
	$count++;
    }
    
    print "\n";
    
    print "Please select the number of the assembly to insert into : ";

    my $num;

    while ($num = <>) {
	chomp($num);
	if ($num >= 1 &&  $num <= scalar(@assemblies)) {
	    last;
	}
    }
    
    my $ass = $assemblies[$num-1];

    return $ass;

}
        

1;

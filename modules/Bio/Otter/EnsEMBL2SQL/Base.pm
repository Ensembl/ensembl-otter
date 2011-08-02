package Bio::Otter::EnsEMBL2SQL::Base;

use strict;
use warnings;
use Carp;

use FileHandle;

use base qw(Bio::EnsEMBL::DBSQL::DBAdaptor);


sub new {
  my ($class,@args) = @_;

  my $self = $class->SUPER::new(@args);

  my ($chr,$start,$end,$type)  = $self->_rearrange([qw(
						       CHR
						       START
						       END
						       TYPE
						       )],@args);



  $self->chromosome($chr) if ($chr);
  $self->start($start)    if ($start);
  $self->end($end)        if ($end);
  $self->type($type)      if ($type);
 

  $self->slice;

  return $self;
}

sub chromosome {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_chromosome} = $arg;
    }

    return $self->{_chromosome};
}


sub start {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_start} = $arg;
    }

    return $self->{_start};
}


sub end {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_end} = $arg;
    }

    return $self->{_end};
}


sub type {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_type} = $arg;
    }

    return $self->{_type};
}

sub query  {
    my ($self,$query) = @_;

    eval {

	my $sth = $self->prepare($query);

	my $res = $sth->execute;
	my $fh = $self->filehandle;

	while (my @row = $sth->fetchrow_array) {
	    my $str;
	    foreach my $r (@row) {
		if (!defined($r) || $r eq "") {
		    $r = "\\N";
		}
		$str .= "$r\t";

	    }
	    chop($str);
	    $str .= "\n";

	    print $fh $str;
	}

    };
    if ($@) {
	$self->throw("Error executing sql $query\n");
    }

    return;
}

sub dump_SQL_to_file {
    my ($self,$dir,$table) = @_;

    my $method = "get_" . $table . "_SQL";

    if ($self->can($method)) {
	printf STDERR "Dumping SQL for %-25s [ %-25s ] using CUSTOM table method\n",$table,$self->dbname;

	my $filehandle = FileHandle->new;

	$filehandle->open(">$dir/$table.sql");

	$self->filehandle($filehandle);

	$self->$method;
	
	$filehandle->close;

    } else {
	printf STDERR "Dumping SQL for %-25s [ %-25s ] using WHOLE  table method\n",$table,$self->dbname;

	my $filehandle = FileHandle->new;

	$filehandle->open(">$dir/$table.sql");

	$self->filehandle($filehandle);

	$self->dump_table($table);

	$filehandle->close;
    }

    return;
}

sub dump_table {
    my ($self,$table) = @_;

    my $sth = $self->prepare("select * from $table");

    my $res = $sth->execute;


    my $fh = $self->filehandle;

    while (my @row = $sth->fetchrow_array) {
	my $str;
	foreach my $r (@row) {
	    if (!defined($r) || $r eq "") {
		$r = "\\N";
	    }
	    $str .= "$r\t";
	}
	chop($str);
	$str .= "\n";

	if (defined($fh)) {
	    print $fh $str;
	}
    }

    return;
}

sub get_dump_stub {
    my ($self,$table) = @_;

    my $command = "mysqldump -c -d " . 
	" -u "    .  $self->username . 
	" -h "    .  $self->host . 
	" -P"     .  $self->port;

    if (defined($self->password) && $self->password ne "") {
	$command .= " -p"     .  $self->password;
    }

    $command .= " "       .  $self->dbname . " $table";

    return $command;
}
    
sub dump_table_SQL {
    my ($self,$table) = @_;

    my $command = $self->get_dump_stub($table);

    open my $in, '-|', $command
        or confess "failed to run the command '$command': $!";
    
    my $str;

    my $fh = $self->filehandle;

    while (<$in>) {
	if (defined($fh)) {
	    print $fh $_;
	} else {
	    $str .= $_;
	}
    }

    close $in
        or confess $! ?
        "error closing the command '$command': $!" :
        "the command '$command' failed: status $?";

    return $str;
}

sub slice {
    my ($self) = @_;

    if (!defined($self->{_slice})) {
	if (!defined($self->chromosome)) {
	    $self->throw("Can't make slice with no chromosome\n");
	} elsif (!defined($self->start)) {
	    $self->throw("Can't make slice with no start coord\n");
	} elsif (!defined($self->end)) {
	    $self->throw("Can't make slice with no end coord\n");
	} elsif (!defined($self->type)) {
	    $self->throw("Can't make slice with no assembly type\n");
	}
	
	$self->assembly_type($self->type);
	
	my $slice = $self->get_SliceAdaptor->fetch_by_chr_start_end(
								    $self->chromosome,
								    $self->start,
								    $self->end);
	
	$self->{_slice} = $slice;
    }

    return $self->{_slice};
    
}

sub filehandle {
    my ($self,$fh) = @_;

    if (defined($fh)) {
	$self->{_fh} = $fh;
    }

    return $self->{_fh};
}


sub get_tables {
    my ($self) = @_;

    if (!defined($self->{_tables})) {
	my $query = "show tables";

	my $sth = $self->prepare($query);
	my $res = $sth->execute;

	my @tables;

	while (my $ref = $sth->fetchrow_arrayref) {
	    push(@tables,$ref->[0]);
	}

	$self->{_tables} = \@tables;
    }

    return $self->{_tables};
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


package Bio::Otter::EnsEMBL2SQL::Base;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

@ISA = qw(Bio::EnsEMBL::DBSQL::DBAdaptor);


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

    my $str;
    eval {

	my $sth = $self->prepare($query);

	my $res = $sth->execute;

	while (my @row = $sth->fetchrow_array) {
	    foreach my $r (@row) {
		$str .= "$r\t";
	    }
	    chop($str);
	    $str .= "\n";
	}
	return $str;
    };
    if ($@) {
	$self->throw("Error executing sql $query\n");
    }

    return $str;
}

sub dump_table {
    my ($self,$table) = @_;

    my $sth = $self->prepare("select * from $table");

    my $res = $sth->execute;

    my $str;

    while (my @row = $sth->fetchrow_array) {
	# Might need some tabs in here
	$str .= "@row\n";
    }

    return $str;
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
    
sub dump_table_create {
    my ($self,$table) = @_;

    my $command = $self->get_dump_stub($table);

    open (IN,"$command |");
    
    my $str;

    while (<IN>) {
	$str .= $_;
    }

    close(IN);

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


	
1;

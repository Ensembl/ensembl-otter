package Bio::Otter::DBSQL::StableIdAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use OtterDefs;
use Bio::Otter::Author;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

my $prefix = $OTTER_PREFIX;   # Configuration in OtterDefs?

sub _fetch_new_by_type {
	my( $self, $type ) = @_;

	my $id     = $type . "_id";
	my $poolid = $type . "_pool_id";
	my $table  = $type . "_stable_id_pool";
	
	my $sql = "insert into $table values(null,'',now())";
	my $sth = $self->prepare($sql);

	my $res = $sth->execute; 

	$sth = $self->prepare("select last_insert_id()");
	$res = $sth->execute;

	my $row = $sth->fetchrow_hashref;

	my $num = $row->{'last_insert_id()'};

	print STDERR "New num for $type is $num\n";

	my $stableid = $prefix;

	if ($type eq "gene") {
	    $stableid .= "G";
	} elsif ($type eq "transcript") {
	    $stableid .= "T";
	} elsif ($type eq "exon") {
	    $stableid .= "E";
	} elsif ($type eq "translation") {
	    $stableid .= "P";
	} else {
	    $self->throw("Unknown stable_id type $type\n");
	}

	my $len = length($num);

	my $pad = 11 - $len;

	my $padstr = '0' x $pad;

	$stableid .= $padstr . $num;
	
	$sth = $self->prepare("update $table set ${type}_stable_id = \' $stableid \' where $poolid = $num");
	$res = $sth->execute;

	$sth->finish;
	$self->throw("Couldn't update $table with new stable id $stableid") unless $res;

	return $stableid;
}

sub fetch_new_gene_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('gene');
}

sub fetch_new_transcript_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('transcript');
}

sub fetch_new_exon_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('exon');
}
sub fetch_new_translation_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('translation');
}


1;

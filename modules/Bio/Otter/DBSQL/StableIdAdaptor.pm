package Bio::Otter::DBSQL::StableIdAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::Author;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);


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

  my $meta_container = $self->db->get_MetaContainer();
  my $min_id  = $meta_container->get_stable_id_min();

  if (defined($min_id)) {

    if ($min_id > $num) {
      my $sql = "update $table set $poolid=$min_id where $poolid=$num";
      my $sth = $self->prepare($sql);
      $res = $sth->execute;
      $num = $min_id;

      $sql = "alter table $table auto_increment= " . ($min_id+1);
      $sth = $self->prepare($sql);
      $res = $sth->execute;
    }
  }

  my $prefix = $meta_container->get_primary_prefix() || "OTT";

  my $stableid = $prefix;

  my $species_prefix = $meta_container->get_species_prefix();
  if (defined($species_prefix)) {
    $stableid .= $species_prefix;
  }

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

  print STDERR "Got new stable id " . $stableid . "\n";
  return $stableid;
}

sub _exists_stable_id_by_type {
    my ($self,$id,$type) = @_;

    my $table  = $type . "_stable_id_pool";
    my $column = $type . "_stable_id";

    my $sql = "select * from $table where $column = '$id'";
    my $sth = $self->prepare($sql);

    my $res = $sth->execute;

    my $row = $sth->fetchrow_hashref;

    if ($sth->rows > 0) {
       return 1;
    } else {
       return 0;
    }
}

sub store_by_type {
  my ($self,$id,$type)  = @_;

  my $table  = $type . "_stable_id_pool";

  if (! $self->_exists_stable_id_by_type($id,$type)) {

     my $sql = "insert into $table values(null,'$id',now())";

     my $sth = $self->prepare($sql);
     my $res = $sth->execute;

     $sth->finish;

     $self->throw("Couldn't update the $table table for $id [$type]") unless $res;
   }
}

sub exists_gene_stable_id {
    my ($self,$id) = @_;

    return $self->_exists_stable_id_by_type($id,'gene');

}
sub exists_transcript_stable_id {
    my ($self,$id) = @_;

    return $self->_exists_stable_id_by_type($id,'transcript');

}
sub exists_tranlation_stable_id {
    my ($self,$id) = @_;

    return $self->_exists_stable_id_by_type($id,'translation');

}
sub exists_exon_stable_id {
    my ($self,$id) = @_;

    return $self->_exists_stable_id_by_type($id,'exon');

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

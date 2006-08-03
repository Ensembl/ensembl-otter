package Bio::Vega::DBSQL::AssemblyTagAdaptor;

use strict;
use Bio::Vega::AssemblyTag;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use base 'Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor';


sub _tables {
  my $self = shift;
  return ['assembly_tag', 'at'];
}

sub _columns {
  my $self = shift;
  return qw(at.tag_id at.seq_region_id at.seq_region_start at.seq_region_end at.seq_region_strand at.tag_type at.tag_info);
}

sub _objs_from_sth {
  my ($self, $sth) = @_;

  #my $rca = $self->db->get_RawContigAdaptor;
  my $sa=$self->db->get_SliceAdaptor();
  my $a_tags = [];

  my $hashref;
  while ($hashref = $sth->fetchrow_hashref()) {

    my $contig = $sa->fetch_by_seq_region_id($hashref->{'seq_region_id'});
    my $atags = Bio::Vega::AssemblyTag->new();

    $atags->seq_region_id($hashref->{seq_region_id});

    $atags->tag_id  ($hashref->{tag_id});
    $atags->strand  ($hashref->{seq_region_strand});
    $atags->start   ($hashref->{seq_region_start});
    $atags->end     ($hashref->{seq_region_end});
    $atags->tag_type($hashref->{tag_type});

    !$hashref->{tag_info} ?  ($atags->tag_info("-")) : ($atags->tag_info($hashref->{tag_info}));

    # contig coords -> chrom. coords
    $atags->attach_seq($contig);
    push @$a_tags, $atags;
  }

  return $a_tags;
}

sub remove {
  my ($self, $del_at) = @_;

  my ( $sth, $val, $sql, $cln_id );

  foreach ( @$del_at ) {

    print STDERR "----- assembly_tag tag_id ", $_->tag_id, " is deleted -----\n";

    $sql = "DELETE FROM assembly_tag where tag_id = ?";
    $val = $_->tag_id;
    $sth = $self->db->prepare($sql);
    $sth->execute($val);

    $sql = "select a.asm_seq_region_id from assembly a, coord_system c, seq_region s where a.cmp_seq_region_id=?".
		     " and a.asm_seq_region_id = s.seq_region_id and s.coord_system_id=c.coord_system_id and c.name='clone'";
    $sth = $self->db->prepare($sql);
    $sth->execute($_->contig_id);
    $cln_id = $sth->fetchrow_array;
    $sth->finish;

    $sql = "DELETE FROM assembly_tagged_clone where clone_id = ?";
    $sth = $self->db->prepare($sql);
    $sth->execute($cln_id);
    $sth->finish;
  }
}

sub store {

  my ($self, $at) = @_;

  if (!ref $at || !$at->isa('Bio::Vega::AssemblyTag') ) {
    throw("Must store an AssemblyTag object, not a $at");
  }
  my $db = $self->db();
  if ($at->is_stored($db)) {
    return $at->dbID();
  }
  my $slice = $at->slice;
  unless ($slice) {
	 throw "AssemblyTag does not have a slice attached to it, cannot store AssemblyTag\n";
  }
  my $csa = $self->db->get_CoordSystemAdaptor();
  my $sa = $self->db->get_SliceAdaptor();
  my $slice_cs = $slice->coord_system;
  unless ($slice_cs) {
	 throw("Coord System not set in assemblytag slice \n");
  }
  my $coord_system_id=$slice->coord_system->dbID();
  unless ( $coord_system_id){
	 my $db_cs;
	 eval{
		$db_cs = $csa->fetch_by_name($slice_cs->name,$slice_cs->version,$slice_cs->rank);
	 };
	 if($@){
		print STDERR "A coord_system matching the arguments does not exist in the coord_system".
		  "table, please ensure you have the right coord_system entry in the database:$@";
	 }
	 my $new_slice = $sa->fetch_by_name($slice->name);
	 unless($new_slice){
		throw "assembly slice is not in the database\n";
	 }
	 $at->slice($new_slice);
  }
  my $tag_info;
  $at->tag_info eq "-" ? ( $tag_info = 'null' ) : ( $tag_info = $at->tag_info );
  my $seq_region_id=$sa->get_seq_region_id($slice);
  my $sql = "INSERT INTO assembly_tag (seq_region_id, seq_region_start, seq_region_end, seq_region_strand, tag_type, tag_info) VALUES (?,?,?,?,?,?)";
  my $sth = $self->prepare($sql);
  $sth->execute($seq_region_id, $at->start, $at->end, $at->strand, $at->tag_type, $tag_info);

  # update also assembly_tagged_clone table, which is initially populated with all clones having transferred col. set to "no"
   my $sql_1 = "select a.asm_seq_region_id from assembly a, coord_system c, seq_region s where a.cmp_seq_region_id=?".
		          " and a.asm_seq_region_id = s.seq_region_id and s.coord_system_id=c.coord_system_id and c.name='clone'";
  my $sth_1 = $self->db->prepare($sql_1);
  $sth_1->execute($seq_region_id);
  my $cln_id = $sth_1->fetchrow_array;
  my $sql_2 = "UPDATE assembly_tagged_clone SET transferred = ? WHERE clone_id = ?";
  my $sth_2 = $self->db->prepare($sql_2);
  $sth_2->execute("yes",$cln_id);
  $sth_2->finish;
  return 1;
}

1;

__END__

=head1 NAME - Bio::Vega::DBSQL::AssemblyTagAdaptor

=head1 AUTHOR

Chao-Kung Chen ck1@sanger.ac.uk

Re-engineered by Sindhu Pillai sp1@sanger.ac.uk

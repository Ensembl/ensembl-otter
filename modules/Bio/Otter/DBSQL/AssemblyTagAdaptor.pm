package Bio::Otter::DBSQL::AssemblyTagAdaptor;

use strict;
use Bio::Otter::AssemblyTag;

use vars qw(@ISA);
@ISA = qw (Bio::EnsEMBL::DBSQL::BaseAdaptor Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor);


=head2 fetch_AssemblyTags_by_Slice

 Title   : fetch_AssemblyTags_by_Slice
 Arg     : slice obj
 Function:
 Returns :list of hash ref to each row of assembly_tag table

=cut

sub fetch_AssemblyTags_by_Slice {
  my ($self, $slice) = @_;

  return $self->fetch_all_by_Slice_constraint($slice);
}

sub _tables {
  my $self = shift;
  return ['assembly_tag', 'at'];
}

sub _columns {
  my $self = shift;
  return qw(at.tag_id at.contig_id at.contig_start at.contig_end at.contig_strand at.tag_type at.tag_info);
}

sub _objs_from_sth {
  my ($self, $sth) = @_;

  my $rca = $self->db->get_RawContigAdaptor;
  my $a_tags = [];

  my $hashref;
  while ($hashref = $sth->fetchrow_hashref()) {

    my $contig = $rca->fetch_by_dbID($hashref->{'contig_id'});

    my $atags = Bio::Otter::AssemblyTag->new();

    #$atags->contig_id($hashref->{contig_id}    );

    $atags->tag_id  ($hashref->{tag_id});
    $atags->strand  ($hashref->{contig_strand});
    $atags->start   ($hashref->{contig_start});
    $atags->end     ($hashref->{contig_end});
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

  my ( $sth, $val );

  foreach ( @$del_at ) {

    print STDERR "----- assembly_tag tag_id ", $_->tag_id, " is deleted -----\n";

    my $sql = "DELETE FROM assembly_tag where tag_id = ?";
    $val = $_->tag_id;
    $sth = $self->db->prepare($sql);
    $sth->execute($val);
  }
}

sub store {
  my ($self, $save_at) = @_;

  my $sql = "INSERT INTO assembly_tag (tag_id, contig_id, contig_start, contig_end, contig_strand, tag_type, tag_info)"
          . " VALUES (?,?,?,?,?,?,?)";

  my ( $sth, @vals );

  if( scalar(@$save_at) == 0 ) {
    warn "Must call store with list of assembly tag objs";
  }

  foreach ( @$save_at ){

    my $tag_info;
    $_->tag_info eq "-" ? ( $tag_info = 'null' ) : ( $tag_info = $_->tag_info );

    @vals = ('', $_->contig_id, $_->start, $_->end, $_->strand, $_->tag_type, $tag_info);

    $sth = $self->db->prepare($sql);
    $sth->execute(@vals);
  }
  return 1;
}

1;

__END__



Chao-Kung Chen ck1@sanger.ac.uk

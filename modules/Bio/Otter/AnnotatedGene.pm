
package Bio::Otter::AnnotatedGene;

use vars qw(@ISA);
use strict;
use warnings;
use base 'Bio::EnsEMBL::Gene';

use Bio::Vega::Utils::XmlEscape qw{ xml_escape xml_unescape };

sub new {
  my($class,@args) = @_;

  my $self = $class->SUPER::new(@args);
  
  my ($gene_info)  = $self->_rearrange([qw(
INFO
)],@args);
  
  $self->gene_info($gene_info);

  return $self;
}

sub gene_type_prefix {
    my ($self, @args) = @_;
    
    $self->throw("Read only method") if @args;
    
    if ($self->type =~ /^([^:]+):/) {
        return $1;
    }
}

sub flush_Transcripts {
    my( $self ) = @_;
    
    $self->{'_transcript_array'} = [];

    return;
}

=head2 gene_info

 Title   : gene_info
 Usage   : $obj->gene_info($newval)
 Function: 
 Example : 
 Returns : value of gene_info
 Args    : newvalue (optional)


=cut

sub gene_info {
   my ($obj,$value) = @_;

   if( defined $value) {

       if ($value->isa("Bio::Otter::GeneInfo")) {
           $obj->{'gene_info'} = $value;
       } else {
           $obj->throw("Argument to gene_info must be a Bio::Otter::GeneInfo object.  Currently is [$value]");
       }
    }
    return $obj->{'gene_info'};

}

=head2 toXMLString

 Title   : toXMLString
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub toXMLString {
    my ($self) = shift;

    # determine if gene is on a slice
    my $exons  = $self->get_all_Exons;
    my $offset = 0;

    if (scalar(@$exons)) {
        my $contig = $exons->[0]->contig;
        if (defined($contig) && $contig->isa("Bio::EnsEMBL::Slice")) {
            $offset = $contig->chr_start - 1;
        }
    }

    my $str      = "<locus>\n";
    $str .= "  <stable_id>" . ($self->stable_id || "") . "</stable_id>\n";

    my $info = $self->gene_info;

    if (my $desc = $self->description) {
        $str .= "  <description>" . xml_escape($desc) . "</description>\n";
    }

    if (defined($info)) {
        my $name = "";
        if (my $n = $info->name) {
            $name = $n->name;
        }
        $str .= "  <name>" . $name . "</name>\n";
        $str .= "  <type>" . $self->type . "</type>\n";

        $str .= "  <known>" . $info->known_flag . "</known>\n";
        $str .= "  <truncated>" . $info->truncated_flag . "</truncated>\n";

        foreach my $syn ($info->synonym) {
            $str .= "  <synonym>" . $syn->name . "<\/synonym>\n";
        }

        foreach my $rem ($info->remark) {
            $str .= "  <remark>" . xml_escape($rem->remark) . "</remark>\n";
        }

        if (my $author = $info->author) {
            $str .= $author->toXMLString;
        }
    }

    my @tran = @{ $self->get_all_Transcripts };

    @tran = sort by_stable_id_or_name @tran;

    foreach my $tran (@tran) {
        $str .= $tran->toXMLString($offset);
    }
    $str .= "</locus>\n";

    return $str;
}


sub by_stable_id_or_name {

  my $astableid = "";
  my $bstableid = "";

  if (defined($a->stable_id)) {$astableid = $a->stable_id;}
  if (defined($b->stable_id)) {$bstableid = $b->stable_id;}
  
  my $cmpVal = ($astableid cmp $bstableid);

  if (!$cmpVal) {
    if (!defined($b->transcript_info->name) && !defined($a->transcript_info->name)) {
      $cmpVal = 0;
    } elsif (!defined($a->transcript_info->name)) {
      $cmpVal = 1;
    } elsif (!defined($b->transcript_info->name)) {
      $cmpVal = -1;
    } else {
      $cmpVal = ($a->transcript_info->name cmp $b->transcript_info->name);
    }
  }
  return $cmpVal;
}

sub stable_id {
  my ($self,$arg) = @_;

  if (defined($arg)) {
    $self->SUPER::stable_id($arg);
    $self->gene_info->gene_stable_id($arg);
  }

  return $self->SUPER::stable_id;
}



=head2 detach_DBAdaptors

    $gene_adaptor->attach_to_Slice($gene, $slice);
    $gene->detach_DBAdaptors;
    $gene_adaptor->store($gene);

Call after C<attach_to_Slice()> and before the
C<store> gene adaptor methods so that lazy
loading methods in the gene components don't
attempt to do lazy loading during the store due
to the presence of adaptors.

=cut

sub detach_DBAdaptors {
    my( $self ) = @_;
    
    # Removes adaptors from genes, transcripts,
    # exons and translations.  May need to add
    # more components it removes adaptors from
    # if we find more lazy loading problems.

    $self->adaptor(undef);
    foreach my $tran (@{$self->get_all_Transcripts}) {
        $tran->adaptor(undef);
        foreach my $exon (@{$self->get_all_Exons}) {
            $exon->adaptor(undef);
        }
        if (my $transl = $tran->translation) {
            $transl->adaptor(undef);
        }
    }

    return;
}

sub length { ## no critic(Subroutines::ProhibitBuiltinHomonyms)
    my( $self ) = @_;
    
    my $exons = $self->get_all_Exons;
    my( $ctg, $gene_start, $gene_end );
    foreach my $exon (@$exons) {
        if ($ctg) {
            if ($exon->contig != $ctg) {
                $self->throw("exons are not all on the same sequence - cannot get length");
            }
        } else {
            $ctg = $exon->contig;
        }
        my $start = $exon->start;
        my $end   = $exon->end;
        if ($gene_start) {
            $gene_start = $start if $start < $gene_start;
        } else {
            $gene_start = $start;
        }
        if ($gene_end) {
            $gene_end = $end if $end > $gene_end;
        } else {
            $gene_end = $end;
        }
    }
    unless ($gene_start and $gene_end) {
        $self->throw(sprintf("Failed to get both gene start (%s) and end (%s)",
            $gene_start || 'NONE', $gene_end || 'NONE'));
    }
    return $gene_end - $gene_start + 1;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


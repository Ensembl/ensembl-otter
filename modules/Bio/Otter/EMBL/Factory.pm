### Bio::Otter::EMBL::Factory
#
# Copyright 2004 Genome Research Limited (GRL)
#
# Maintained by Mike Croning <mdr@sanger.ac.uk>
#
# You may distribute this file/module under the terms of the perl artistic
# licence
#
# POD documentation main docs before the code. Internal methods are usually
# preceded with a _
#

=head1 NAME
 
Bio::Otter::EMBL::Factory
 
=head2 Constructor:

my $factory = Bio::Otter::EMBL::Factory->new;

=cut

package Bio::Otter::EMBL::Factory;


use strict;
use Carp;
use Hum::EMBL;
use Hum::EmblUtils qw( add_source_FT add_Organism);


=head2 new

my $factory = Bio::Otter::EMBL::Factory->new;

=cut
	
sub new {
    my( $pkg ) = @_;
     
    return bless {}, $pkg;
}


=head2 organism_lines
 
?? 

=cut

sub organism_lines {

}


=head2 standard_comments
 
?? 

=cut

sub standard_comments {

}


=head2 make_embl
 
This is the big one!

=cut

sub make_embl {
    my ( $self, $acc ) = @_;
    
    confess "Must pass an accession" unless $acc;
    
    my $ds = $self->Dataset
        or confess "Dataset must be set before calling make_embl";

    my ($otter_db, $slice_aptr, $gene_aptr) = $self->get_DBAdaptors();
    
    my $embl = Hum::EMBL->new();
    
    foreach my $chr_s_e ($self->fetch_chr_start_end_for_accession($otter_db, $acc)) {

        print "ACC: $acc ";  
        print "Chr: ", $chr_s_e->[0], " Start: ", $chr_s_e->[1], " End: ", $chr_s_e->[2], "\n";

        #Get the Bio::EnsEMBL::Slice
        my $slice = $slice_aptr->fetch_by_chr_start_end(@$chr_s_e);

        my $gene_id_list = $gene_aptr->list_current_dbIDs_for_Slice($slice);
        my $tile_path = $self->get_tiling_path_for_Slice($slice);


     }
        
    return $embl;
}


=head2 get_tiling_path_for_Slice

Wraps $slice->get_tiling_path, additionally checking there
is only 1 in component in the retrieved tiling_path

=cut

sub get_tiling_path_for_Slice {
    my ( $self, $slice ) = @_;
    
    my $tile_path = $slice->get_tiling_path;
    
    if (@$tile_path != 1) {
        my $count = @$tile_path;
        confess "Expected 1 component in tiling_path but have $count\n";
    }
    
    return $tile_path;
}

=head2 get_DBAdaptors

    my ($otter_db, $slice_aptr, $gene_aptr) = get_DBAdaptors();

Providing $self->Dataset has been set, retrieves the cached DBAdaptor
from the Dataset, together with Slice and Gene adaptors.

=cut

sub get_DBAdaptors {
    my ( $self ) = @_;

    my $ds = $self->Dataset
        or confess "Dataset not set";
    
    #Bio::EnsEMBL::Container    
    my $otter_db = $ds->get_cached_DBAdaptor
        or confess 'Bio::Otter::Lace::DataSet->get_cached_DBAdaptor failed';
    
    #Bio::EnsEMBL::DBSQL::SliceAdaptor
    my $slice_aptr = $otter_db->get_SliceAdaptor
        or confess "get_SliceAdaptor failed";
        
    #Bio::EnsEMBL::DBSQL::ProxyGeneAdaptor
    my $gene_aptr  = $otter_db->get_GeneAdaptor
        or confess "get_GeneAdaptor failed";
    
    return ($otter_db, $slice_aptr, $gene_aptr);        
}


=head2 Dataset
 
Get/set method for the 'Bio::Otter::Lace::Dataset' object
used to access the Otter database.

=cut

sub Dataset {
    my ( $self, $obj ) = @_;
    
    if ($obj) {
        unless ($obj->isa('Bio::Otter::Lace::DataSet')) {
            confess "Must pass a 'Bio::Otter::Lace::DataSet' object\n";
        }
        $self->{'_bio_otter_embl_factory_dataset'} = $obj;
    }
    return $self->{'_bio_otter_embl_factory_dataset'};
}


=head2 fetch_chr_start_end_for_accession

When passed an Otter DBAdaptor and a Clone accession,
Returns an array of arrays of [chr, start, end]

eg. Such as [1, 561232, 672780]

=cut

sub fetch_chr_start_end_for_accession {
    my( $self, $db, $acc ) = @_;
    
    
    my $type = $db->assembly_type;
    
    my $sth = $db->prepare(q{
        SELECT chr.name
          , a.chr_start
          , a.chr_end
        FROM assembly a
          , contig c
          , clone cl
          , chromosome chr
        WHERE c.clone_id = cl.clone_id
          AND c.contig_id = a.contig_id
          AND chr.chromosome_id = a.chromosome_id
          AND cl.embl_acc = ?
          AND a.type = ?
        ORDER BY a.chr_start
        });
    $sth->execute($acc, $type);
    
    my( @chr_start_end );
    while (my ($chr, $start, $end) = $sth->fetchrow) {
        push(@chr_start_end, [$chr, $start, $end]);
    }
    if (@chr_start_end) {
        return @chr_start_end;
    } else {
        die "Clone with accession '$acc' not found on assembly '$type'\n";
    }
}


1;

__END__
 
=head1 NAME - Bio::Otter::EMBL::Factory
 
=head1 AUTHOR
 
Mike Croning B<email> mdr@sanger.ac.uk
 

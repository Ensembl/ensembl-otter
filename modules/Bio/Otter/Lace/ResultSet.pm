### Bio::Otter::Lace:ResultSet
## this object is used to store the results of a search for a particular clone.
## sequence sets are now stored in an array 
## so they should come out in order, but there is no check that for an existing sequence set

package Bio::Otter::Lace::ResultSet;
use Data::Dumper ;
use strict;
use Carp;

sub new {
    my $pkg = shift;
    
    return bless {}, $pkg;
}


sub add_SequenceSet{
    my ($self, $ss) = @_ ;
    
    unshift @{$self->{'sequence_set'} }  , $ss ;  
}

sub get_SequenceSet_by_name{
    my ($self , $name ) = @_ ;
    
    foreach my $ss ( @{$self->{'sequence_set'}} ){

        if ($ss->name eq $name) {
            return $ss;
        }
    }
}

sub get_all_SequenceSets{
    my ($self) = @_ ;
    
    my $list  = $self->{'sequence_set'} ;
    
    return $list
}

sub search_array{
    my ($self , $string) = @_ ;
    if ($string){
        $self->{'_search_string'} = $string ;           
    }
    return $self->{'_search_string'}; 
}

sub search_type{
    my ($self , $type) = @_;

    if ($type){
        $self->{'search_type'} = $type ;
    }
    return $self->{'search_type'};
}

sub DESTROY{
    warn "Destroying ResultSet" ;
}

1 ;


### Bio::Otter::Lace:ResultSet
## this object is used to store the results of a search for a particular clone.

package Bio::Otter::Lace::ResultSet;
use Data::Dumper ;
use strict;
use Carp;

sub new {
    my $pkg = shift;
    
    return bless {}, $pkg;
}

my $number ;
sub add_SequenceSet{
    my ($self, $ss) = @_ ;
    
    my $name = $ss->name ;     
    $number = 1 unless defined $number  ;
    $number ++ ;
    
    $self->{'sequence_set'}->{$name}  = $ss  ;
    
}

sub get_SequenceSet_by_name{
    my ($self , $name ) = @_ ;
    
    my $hash = $self->{'sequence_set'} ;
    
    my $ss = $hash->{$name} ;
    
    if (defined $ss) {
        return $ss;
    }else{ 
        return ;
    }
}

sub get_all_SequenceSets{
    my ($self) = @_ ;
    my @list ;
    while (my ($name, $ss) = each (%{$self->{'sequence_set'}})){
        push(@list , $ss) ;
    }
    return \@list
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

1 ;


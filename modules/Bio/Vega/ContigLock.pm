package Bio::Vega::ContigLock;

### Maybe simpler for each Lock to have-a Clone and an Author
### (instead of a clone_id)?

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base qw(Bio::EnsEMBL::Storable);

sub new {
    my ($class, @args) = @_;
    
    my $self = $class->SUPER::new(@args);

    my ($contig_id, $author, $timestamp, $hostname) = rearrange(
        [qw{ CONTIG_ID AUTHOR TIMESTAMP HOSTNAME }], @args);

    $self->contig_id($contig_id);
    $self->author($author);
    $self->timestamp($timestamp);
    $self->hostname($hostname);

    return $self;
}

sub contig_id {
    my ($self, $contig_id) = @_;
    if ($contig_id) {
        $self->{'contig_id'} = $contig_id;
    }
    return $self->{'contig_id'};
}

sub author{
   my ($self, $value) = @_;
   if( defined $value) {
       if ($value->isa("Bio::Vega::Author")) {
           $self->{'author'} = $value;
       } else {
           throw("Argument [$value] is not a Bio::Vega::Author");
       }
   }
   return $self->{'author'};
}

sub timestamp{
   my ($obj, $value) = @_;
   if( defined $value) {
      $obj->{'timestamp'} = $value;
    }
    return $obj->{'timestamp'};
}

sub hostname {
    my ($self, $hostname) = @_;
    if ($hostname) {
        $self->{'hostname'} = $hostname;
    }
    return $self->{'hostname'};
}



1;



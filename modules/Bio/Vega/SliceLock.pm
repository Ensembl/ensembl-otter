package Bio::Vega::SliceLock;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base qw(Bio::EnsEMBL::Storable);

=head1 NAME

Bio::Vega::SliceLock - a lock on part of a seq_region

=head1 DESCRIPTION

This behaves like a read-only feature.  Changes are made through its
broker.

=cut

sub new {
    my ($class, @args) = @_;

    my $self = $class->SUPER::new(@args);

    my ($slice_id, $author, $timestamp, $hostname) = rearrange(
        [qw{ SLICE_ID AUTHOR TIMESTAMP HOSTNAME }], @args);

    $self->slice_id($slice_id);
    $self->author($author);
    $self->timestamp($timestamp);
    $self->hostname($hostname);

    return $self;
}

sub slice_id {
    my ($self, $slice_id) = @_;
    if ($slice_id) {
        $self->{'slice_id'} = $slice_id;
    }
    return $self->{'slice_id'};
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

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


### Bio::Vega::HitDescription

package Bio::Vega::HitDescription;

use strict;
use warnings;

use warnings;

use Bio::EnsEMBL::Utils::Argument  qw( rearrange );

sub new {
    my ($caller, @args) = @_;

    my ($hit_name, $hit_length, $description, $taxon_id, $db_name) = rearrange(
      [ 'HIT_NAME', 'HIT_LENGTH', 'DESCRIPTION', 'TAXON_ID', 'DB_NAME' ], @args);
    my $class = ref($caller) || $caller;
    return bless {
        _hit_name       => $hit_name,
        _hit_length     => $hit_length,
        _description    => $description,
        _taxon_id       => $taxon_id,
        _db_name        => $db_name,
    }, $class;
}

sub hit_name {
    my( $self, $hit_name ) = @_;
    
    if ($hit_name) {
        $self->{'_hit_name'} = $hit_name;
    }
    return $self->{'_hit_name'};
}

sub hit_length {
    my( $self, $hit_length ) = @_;
    
    if ($hit_length) {
        $self->{'_hit_length'} = $hit_length;
    }
    return $self->{'_hit_length'};
}

sub description {
    my( $self, $description ) = @_;
    
    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub taxon_id {
    my( $self, $taxon_id ) = @_;
    
    if ($taxon_id) {
        $self->{'_taxon_id'} = $taxon_id;
    }
    return $self->{'_taxon_id'};
}

sub db_name {
    my( $self, $db_name ) = @_;
    
    if ($db_name) {
        $self->{'_db_name'} = $db_name;
    }
    return $self->{'_db_name'};
}


1;

__END__

=head1 NAME - Bio::Vega::HitDescription

=head1 DESCRIPTION

The HitDescription object provides extra
information about database matches that is not
provided by the AlignFeature objects to which it
is attached.

=head1 METHODS

=over 4

=item hit_length

The length of the entire hit sequence - not just
the region matched.

=item description

A one line description of the sequence.

=item taxon_id

The numeric NCBI taxonomy database ID for the
node (which is usually species).

=item db_name

The database which the hit belongs to.

=back

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


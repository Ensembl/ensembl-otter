
### Bio::Otter::HitDescription

package Bio::Otter::HitDescription;

use strict;

sub new {
    return bless {}, shift;
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

sub get_option_order { # standard order of options for stringification
return [
        ## (The commented out ones need special treatment)
        # qw(name),
        qw(hit_length description taxon_id db_name),
    ];
}


1;

__END__

=head1 NAME - Bio::Otter::HitDescription

=head1 DESCRIPTION

The HitDescription object provides extra
information about database matches that is not
provided by the AlignFeature objects to which it
is attached.

=head1 MEHTODS

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

James Gilbert B<email> jgrg@sanger.ac.uk


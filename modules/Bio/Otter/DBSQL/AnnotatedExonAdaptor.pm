
### Bio::Otter::DBSQL::AnnotatedExonAdaptor

package Bio::Otter::DBSQL::AnnotatedExonAdaptor;

use strict;
use base 'Bio::EnsEMBL::DBSQL::ExonAdaptor';

# override fetch_by_stable_id to get most recent

sub fetch_by_stable_id {
    my( $self, $stable_id ) = @_;

    my $sth = $self->prepare(q{
        SELECT exon_id
        FROM exon_stable_id
        WHERE stable_id = ?
        ORDER BY version DESC LIMIT 1
        });
    $sth->execute($stable_id);
    if (my ($db_id) = $sth->fetchrow) {
        my $exon = $self->fetch_by_dbID($db_id);
        return $exon;
    } else {
        $self->warn("No Exon with stable_id '$stable_id' in the database!");
        return undef;
    }
}

1;

__END__

=head1 NAME - Bio::Otter::DBSQL::AnnotatedExonAdaptor

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


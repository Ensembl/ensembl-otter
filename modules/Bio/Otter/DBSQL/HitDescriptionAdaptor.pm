
### Bio::Otter::DBSQL::HitDescriptionAdaptor

package Bio::Otter::DBSQL::HitDescriptionAdaptor;

use strict;
use Bio::Otter::HitDescription;
use base 'Bio::EnsEMBL::DBSQL::BaseAdaptor';

sub fetch_HitDescriptions_into_hash {
    my( $self, $hash ) = @_;
    
    my $sql = qq{
        SELECT hit_name
          , hit_length
          , hit_description
          , hit_taxon
          , hit_db
        FROM hit_description
        WHERE hit_name IN (
        };
    $sql .= join(',', map "'$_'", keys %$hash);
    $sql .= qq{\n)};
    #warn $sql;
    
    my $sth = $self->prepare($sql);
    $sth->execute;

    my( $name, $length, $desc, $taxon_id, $db_name );
    $sth->bind_columns(\$name, \$length, \$desc, \$taxon_id, \$db_name);

    while ($sth->fetch) {
        $hash->{$name} = bless
            {
                _hit_length     => $length,
                _description    => $desc,
                _taxon_id       => $taxon_id,
                _db_name        => $db_name,
            }, 'Bio::Otter::HitDescription';
    }
}

1;

__END__

=head1 NAME - Bio::Otter::DBSQL::HitDescriptionAdaptor

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


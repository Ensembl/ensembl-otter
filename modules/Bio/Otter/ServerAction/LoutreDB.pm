package Bio::Otter::ServerAction::LoutreDB;

use strict;
use warnings;

use base 'Bio::Otter::ServerAction';

=head1 NAME

Bio::Otter::ServerAction::LoutreDB - serve requests for info from loutre db.

=cut

# Parent constructor is fine unaugmented.

### Methods

=head2 get_meta
=cut

my $select_meta_sql = <<'SQL'
    SELECT species_id, meta_key, meta_value
      FROM meta
  ORDER BY meta_id
SQL
    ;

my @white_list = qw(
    assembly
    patch
    prefix
    schema_type
    schema_version
    species
);

my %white_list = map { $_ => 1 } @white_list;

sub get_meta {
    my $self = shift;

    my $sth = $self->server->otter_dba()->dbc()->prepare($select_meta_sql);
    $sth->execute;

    my $counter = 0;
    my @results;

    while (my ($species_id, $meta_key, $meta_value) = $sth->fetchrow) {

        my ($key_prefix) = $meta_key =~ /^(\w+)\.?/;
        next unless $white_list{$key_prefix};

        $meta_value=~s/\s+/ /g; # get rid of newlines and tabs

        push @results, { meta_key => $meta_key, meta_value => $meta_value, species_id => $species_id };
        $counter++;
    }

    warn "Total of $counter meta table pairs whitelisted\n";

    return $self->serialise_output(\@results);
}

# Null serialiser, overridden in B:O:SA:TSV::LoutreDB
sub serialise_output {
    my ($self, $results) = @_;
    return $results;
}

### Accessors

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;


package Bio::Otter::Server::GFF::GRCIssues;

use strict;
use warnings;

use base qw( Bio::Otter::Server::GFF Bio::Otter::Server::GFF::Utils );

use Bio::EnsEMBL::Attribute;
use Bio::EnsEMBL::MiscFeature;

sub Bio::EnsEMBL::Slice::get_all_GRC_issues {
    my ($slice, $server, $sth, $chr_name) = @_;

    my $chr_start = $slice->start();
    my $chr_end   = $slice->end();

    $sth->execute($chr_name, $chr_start, $chr_end);

    my @feature_coll;

    my $rows = 0;

    while (my $issue = $sth->fetchrow_hashref) {

        ++$rows;
        my $fp = Bio::EnsEMBL::MiscFeature->new_fast({});

        $fp->slice(      $slice );

        $fp->start(      $issue->{start} - $chr_start + 1 );
        $fp->end(        $issue->{end}   - $chr_start + 1 );
        $fp->strand(     1 );

        my $note = sprintf '%s: %s (%s)', @{$issue}{ qw( category description status ) };
        $fp->add_Attribute(_make_attrib('name', $issue->{jira_id}));
        $fp->add_Attribute(_make_attrib('note', $note));

        push @feature_coll, $fp;
    }

    warn "got $rows issue features\n";

    return \@feature_coll;
}

# Not a method!
sub _make_attrib {
    my ($code, $value) = @_;
    return Bio::EnsEMBL::Attribute->new(
        -CODE  => $code,
        -VALUE => $value,
        );
}

sub get_requested_features {
    my ($self) = @_;

    my ($dbh, $db_table) = $self->db_connect;

    my $sth = $dbh->prepare(qq{
    SELECT
        jira_id,
        category,
        report_type,
        status,
        description,
        chr,
        start,
        end
    FROM
        $db_table
    WHERE
            chr    = ?
        AND end   >= ?
        AND start <= ?
    ORDER BY
        start ASC
    });

    my $chr_name      = $self->param('name');
    my $map = $self->make_map;

    my $features = $self->fetch_mapped_features_das(
        'get_all_GRC_issues',
        [$self, $sth, $chr_name],
        $map);

    return $features;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


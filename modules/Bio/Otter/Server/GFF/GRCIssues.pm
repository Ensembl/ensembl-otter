=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


package Bio::Otter::Server::GFF::GRCIssues;

use strict;
use warnings;

use base qw( Bio::Otter::Server::GFF Bio::Otter::Server::GFF::Utils );

use Bio::EnsEMBL::MiscFeature;
use Bio::Vega::Utils::Attribute qw( make_EnsEMBL_Attribute );
use Bio::Vega::Utils::Detaint   qw( detaint_url_fmt );

sub Bio::EnsEMBL::Slice::get_all_GRC_issues {
    my ($slice, $server, $sth, $chr_name) = @_;

    my $chr_start = $slice->start();
    my $chr_end   = $slice->end();

    $sth->execute($chr_name, $chr_start, $chr_end);

    my @feature_coll;

    my $rows = 0;

    my $url_string = $server->param('url_string');
    my $url_base;
    if ($url_string) {
        $url_base = detaint_url_fmt($url_string);
        die "Cannot detaint url_string='$url_string'" unless $url_base;
    }

    while (my $issue = $sth->fetchrow_hashref) {

        ++$rows;
        my $fp = Bio::EnsEMBL::MiscFeature->new_fast({});

        $fp->slice(      $slice );

        $fp->start(      $issue->{start} - $chr_start + 1 );
        $fp->end(        $issue->{end}   - $chr_start + 1 );
        $fp->strand(     1 );

        my $name = $issue->{jira_id};
        my $note = sprintf '%s: %s (%s)', @{$issue}{ qw( category description status ) };
        $fp->add_Attribute(make_EnsEMBL_Attribute('name', $name));
        $fp->add_Attribute(make_EnsEMBL_Attribute('note', $note));

        if ($url_base) {
            my $url = sprintf("$url_base", $name);
            $fp->add_Attribute(make_EnsEMBL_Attribute('url', $url));
        }

        push @feature_coll, $fp;
    }

    warn "got $rows issue features\n";

    return \@feature_coll;
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


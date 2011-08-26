
package Bio::Otter::Server::GFF::PslSql;

use strict;
use warnings;

use base qw( Bio::Otter::Server::GFF );

use Bio::EnsEMBL::DnaDnaAlignFeature;

sub Bio::EnsEMBL::Slice::get_all_features_via_psl_sql {
    my ($slice, $server, $sth, $chr_name) = @_;

    my $chr_start = $slice->start();
    my $chr_end   = $slice->end();

    my $search_name = sprintf('chr%s', $chr_name); # how to handle this via config?

    $sth->execute($search_name, $chr_start, $chr_end);

    my @feature_coll;

    while (my $psl_row = $sth->fetchrow_hashref) {

        # Remember:
        # When we get to splitting up the features, we need to discard ones which don't overlap segment

#         if ($das_feature->{'end'} < $chr_start) {
#             $truncated_5_prime = 1;
#         }

#         if ($das_feature->{'start'} > $chr_end) {
#             $truncated_3_prime = 1;
#         }

        my $f_score = '-';      # no score in psl

        my $f_start = $psl_row->{tStart} + 1;
        my $f_end   = $psl_row->{tEnd};

        my $feature = Bio::EnsEMBL::DnaDnaAlignFeature->new_fast({});

        $feature->slice(   $slice );

        # Set feature start and end to start and end of segment if it extends beyond
        $feature->start( $f_start < $chr_start ? 1        : $f_start - $chr_start + 1 );
        $feature->end(   $f_end   > $chr_end   ? $chr_end : $f_end   - $chr_start + 1 );
        $feature->strand( $psl_row->{strand} =~ /^-/ ? -1 : 1 );

        if($feature->can('score')) {
            ## should we fake the value when it is not available? :
            $feature->score( ($f_score eq '-') ? 100 : $f_score );
        }

        $feature->display_id( $psl_row->{qName} );

        push @feature_coll, $feature;
    }

    warn "got ", scalar(@feature_coll), " features\n";

    return \@feature_coll;
}

sub get_requested_features {
    my ($self) = @_;

    my $chr_name      = $self->param('name');  ## Since in our new schema name is substituted for type,
    ## we need it clean for outer sources

    my $dsn           = $self->require_argument('dsn');
    my $db_user       = $self->require_argument('db_user');
    my $db_table      = $self->require_argument('db_table');

    my $dbh = DBI->connect($dsn, $db_user);
    my $sth = $dbh->prepare(qq{
    SELECT
        matches,
        misMatches,
        repMatches,
        nCount,
        qNumInsert,
        qBaseInsert,
        tNumInsert,
        tBaseInsert,
        strand,
        qName,
        qSize,
        qStart,
        qEnd,
        tName,
        tSize,
        tStart,
        tEnd,
        blockCount,
        blockSizes,
        qStarts,
        tStarts
    FROM
        ${db_table}
    WHERE
            tName   = ?
        AND tEnd   >= ?
        AND tStart <= ?
    ORDER BY
        tStart ASC
    });

    my $map = $self->make_map;
    my $features = $self->fetch_mapped_features_das(
        'get_all_features_via_psl_sql',
        [$self, $sth, $chr_name],
        $map);

    return $features;
}

1;

__END__

=head1 AUTHOR

Michael Gray B<email> mg13@sanger.ac.uk


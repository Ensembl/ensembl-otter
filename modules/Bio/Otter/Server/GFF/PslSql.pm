
package Bio::Otter::Server::GFF::PslSql;

use strict;
use warnings;

use List::Util qw(max min);
use Readonly;
Readonly my $INTRON_MIN => 8;

use Data::Dumper;               # REMEMBER to delete when done debugging

use base qw( Bio::Otter::Server::GFF );

use Bio::EnsEMBL::DnaDnaAlignFeature;

# NOT a method
#
sub _psl_adjust_start_for_strand {
    my ($q_start, $q_size, $positive) = @_;

    if ($positive) {
        return $q_start + 1;
    }
    else {
        return $q_size - $q_start;
    }
}

# NOT a method - but probably should be, of a PSL utility class
#
sub _psl_get_next_block {
    my ($block_lists, $q_size, $positive) = @_;

    return unless (@{$block_lists->{sizes}} and @{$block_lists->{q_starts}} and @{$block_lists->{t_starts}});

    my $length      = shift(@{$block_lists->{sizes}});
    my $raw_q_start = shift(@{$block_lists->{q_starts}});
    my $raw_t_start = shift(@{$block_lists->{t_starts}});

    my %block;

    $block{q_start} = _psl_adjust_start_for_strand($raw_q_start, $q_size, $positive);
    $block{t_start} = $raw_t_start + 1;
    $block{length}  = $length;

    $block{q_end}   = $positive ? ($block{q_start} + $length - 1) : ($block{q_start} - $length + 1);
    $block{t_end}   = $block{t_start} + $length - 1;

    $block{cigar}   = $length == 1 ? 'M' : $length . 'M';

    warn "Returning block:\n", Dumper(\%block);

    return \%block;
}

# NOT a method
#
sub _psl_split_gapped_feature {
    my $psl = shift;

    my @features;

    my $strand = $psl->{strand};
    my $positive = ($strand eq '+');

    my $q_size      = $psl->{qSize};
    my $block_count = $psl->{blockCount};
    my $block_sizes = $psl->{blockSizes};
    my $q_starts    = $psl->{qStarts};
    my $t_starts    = $psl->{tStarts};

    # Much of the inital processing is nicked from Bio::SearchIO::psl
    #

    # cleanup trailing commas in some output
    $block_sizes =~ s/\,$//;
    $q_starts    =~ s/\,$//;
    $t_starts    =~ s/\,$//;

    my @blocksizes = split( /,/, $block_sizes );    # block sizes
    my @qstarts = split( /,/, $q_starts ); # starting position of each block in query
    my @tstarts = split( /,/, $t_starts ); # starting position of each block in target

    my %blocks = ( sizes => \@blocksizes, q_starts => \@qstarts, t_starts => \@tstarts );

    warn("Starting split for ", $psl->{qName}, "\n");

    my $prev = _psl_get_next_block(\%blocks, $q_size, $positive);

    # Start with a copy of the initial block. There may only be one, after all
    my $current = { %$prev };

    while (my $this = _psl_get_next_block(\%blocks, $q_size, $positive)) {

        my $q_intron_len = abs( $this->{q_start} - $prev->{q_end} ) - 1;
        my $t_intron_len = $this->{t_start} - $prev->{t_end} - 1;

        if (    $t_intron_len < $INTRON_MIN
                and $q_intron_len < $INTRON_MIN
                and ($t_intron_len == 0 or $q_intron_len == 0 or $t_intron_len == $q_intron_len)
            ) {

            # Treat as gap - extend $current and its cigar string
            #
            $current->{t_end}   = $this->{t_end};

            $current->{q_start} = min($current->{q_start}, $this->{q_start});
            $current->{q_end}   = max($current->{q_end},   $this->{q_end});

            if ($q_intron_len > 0) {
                # extra bases in query == insertions in target (can't do) == deletions from query
                $current->{cigar} .= $q_intron_len == 1 ? 'D' : $q_intron_len . 'D';
            } elsif ($t_intron_len > 0) {
                # extra bases in target == insertions in query to make match
                $current->{cigar} .= $t_intron_len == 1 ? 'I' : $t_intron_len . 'I';
            } else {
                # BAD PSL
                warn("Bad blocks list in PSL item.\n");
            }

            $current->{cigar} .= $this->{cigar};

        } else {

            # Treat as intron - add the current feature to the list and restart
            #
            warn("Ending exon, cigar: ", $current->{cigar}, "\n");
            push @features, $current;
            $current = { %$this };

        }

        $prev = $this;
    }

    warn("Ending final exon, cigar: ", $current->{cigar}, "\n");
    push @features, $current;   # make sure to get the last (or only) block

    warn("Returning ", scalar(@features), " features from ", $psl->{qName}, "\n");
    return @features;
}

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

        $feature->hstart(       $psl_row->{qStart} + 1 );
        $feature->hend(         $psl_row->{qEnd}       );
        $feature->hstrand(      1                      );
        $feature->hseqname(     $psl_row->{qName}      );
        $feature->cigar_string( sprintf('%dM', $psl_row->{qSize}) ); # assume it's all match for now

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

sub parse_dsn {
    my ($self, $dsn) = @_;

    # E.g.:
    #     'DBI:mysql:database=hg19;host=genome-mysql.cse.ucsc.edu;user=genome'
    # => ('DBI:mysql:database=hg19;host=genome-mysql.cse.ucsc.edu', 'genome')

    my ($dbi, $driver, $spec) = split(':', $dsn);

    my %spec_parts;
    foreach my $part (split(';', $spec)) {
        my ($key, $value) = split('=', $part);
        $spec_parts{$key} = $value;
    }

    my $user = $spec_parts{user};
    delete $spec_parts{user};

    $spec = join( ';', map { join('=', $_, $spec_parts{$_}) } keys %spec_parts );
    $dsn  = join(':', $dbi, $driver, $spec);

    return ($dsn, $user);
}

sub get_requested_features {
    my ($self) = @_;

    my $chr_name      = $self->param('name');  ## Since in our new schema name is substituted for type,
    ## we need it clean for outer sources

    # I abuse dsn and source args to avoid having to add new arg types to Bio::Otter::Filter,
    # and they have different meanings for DAS sources, which I try to preserve.
    #
    my $req_dsn       = $self->require_argument('dsn');
    my $req_source    = $self->require_argument('source');

    my $db_table = $req_dsn;
    my ($dsn, $db_user) = $self->parse_dsn($req_source);

    warn(sprintf("Connecting to '%s' %s, table %s\n",
                 $dsn, $db_user ? "as '${db_user}'" : "[no user]", $db_table));

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


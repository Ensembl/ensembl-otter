#! /software/bin/perl-5.12.2
use strict;
use warnings;

use Test::More;
use YAML 'Dump';
use GDBM_File;
use t::lib::Test::Otter qw( ^db_or_skipall get_BOLDatasets diagdump );

use File::Temp 'tempfile';
use LWP::UserAgent;
use Digest::MD5 'md5_hex';
use Bio::SeqIO;


=head1 DESCRIPTION

Check the sequence (its md5sum) and length of all clones for species.

Sequence data is fetched through a cache file, from pfetch and falling
back on EMBL SVA.

=head1 AUTHOR

mca@sanger.ac.uk

=cut


sub main {
    @ARGV = qw(pig) unless @ARGV;
    my @ds = get_BOLDatasets(@ARGV);
    plan tests => 1 * @ds;

    foreach my $ds (@ds) {
        my $name = $ds->name;
        my $O = $ds->get_cached_DBAdaptor;

        my $clones = $O->get_SliceAdaptor->fetch_all(clone => undef, 1, 1, 1);
        subtest "Whole clones in $name" => sub {
            plan tests => 1 * @$clones;
            _cache_init($name);
            my $fail = species_tt($ds, $clones);
            _cache_drop();
            diagdump(fail => $fail) if keys %$fail;
        };
    }
}


sub species_tt {
    my ($ds, $clones) = @_;
    my $dbname;

    my %fail;
    while (my $cl = shift @$clones) {
        $dbname ||= $cl->adaptor->dbc->dbname;
        my $rname = $cl->seq_region_name;

# XXX: tell what chromosome(s) it's on
        my ($info, @bad) = check_clone($cl, $clones);
        my $test = "$dbname: $rname";
        ok(scalar @bad == 0, $test);

        if (@bad) {
            if ("@bad" eq 'no data') {
                # not so interesting
                push @{ $fail{'no data'} }, $rname;
            } elsif (1 == @bad) {
                # collect like problems
                $fail{$bad[0]}{$rname} = $info;
            } else {
                # more complex
                $fail{$test} = [ $info, @bad ];
            }

            # debug hook: see what's going on early
            diagdump(bad => \@bad, info => $info) if $ENV{TEST_EARLY};
        }
    }

    return \%fail;
}


sub check_clone {
    my ($cl, $upcoming) = @_;
    my $rname = $cl->seq_region_name;
    my $srid = $cl->get_seq_region_id;

    # Find sequence this clone, stored at contig level.  Assume there
    # is a contig covering the entire clone.
    # Doesn't cope with compressed sequence (dnac)
    my $R = $cl->adaptor->dbc->db_handle->selectall_arrayref(q{
 SELECT r.seq_region_id, r.name, r.length, cs.name, length(d.sequence), md5(d.sequence)
 FROM seq_region r
   JOIN dna d USING (seq_region_id)
   JOIN coord_system cs USING (coord_system_id)
 WHERE r.name = ? }, {}, (join '.', $rname, $cl->start, $cl->end));

    return ({ rows => $R,  },
            sprintf('fetching: want 1 match, got %s', scalar @$R))
      unless 1 == @$R;

    my $pmd5 = pfetch_md5($cl, $upcoming);
    die "Fetcher breakage on $rname" unless defined $pmd5;
    my @b0rk;
    my ($id, $n, $rlen, $cs, $dlen, $dmd5) = @{ $R->[0] };

    push @b0rk, "length fail" unless $rlen == $dlen;
    push @b0rk, "sr.name: expect $rname.1.$rlen, got $n" unless $n eq "$rname.1.$rlen";
    push @b0rk, "cs.name: expect 'contig', got $cs" unless $cs eq 'contig';
    if ($dmd5 eq $pmd5) {
        # OK
    } elsif ($pmd5 =~ m{^!}) {
        push @b0rk, 'no data';
    } else {
        push @b0rk, 'md5 fail';
    }

    my %info =
      ('dna.sequence,md5' => $dmd5, 'original,md5' => $pmd5,
       seq_region_id => $id,
       'seq_region.name' => $n,
       'seq_region.length' => $rlen, 'dna.sequence,len' => $dlen,
       'coord_system.name' => $cs);

    return (\%info, @b0rk);
}


# It was just a big global cache for optimisation.
# Now it's a big mess that wants to be an object.
{
    our ($species, %pfetch_cache);
    sub _cache_init {
        ($species) = @_;
        my $fn = "pfetch-md5.cache=$species.gdbm";
        $SIG{INT} = sub { die "Caught SIGINT - flushing $fn\n" };
        tie %pfetch_cache, 'GDBM_File', $fn, GDBM_WRCREAT, 0644;
        # nb. GDBM doesn't store undef

        _summarise('start');
        _fixups();
    }

    sub _cache_drop {
        _summarise('end');
        untie %pfetch_cache;
    }

    sub _fixups {
        foreach my $k (keys %pfetch_cache) {
            next if $pfetch_cache{$k} =~ m{^[0-9a-f]{32}$}; # good
            next if $k =~ m{\.Contig\d+\.}; # known bad
            warn "  Cache evict for $k\n";
            $pfetch_cache{$k} = ''; # try again!
        }
    }

    sub _summarise {
        my ($t) = @_;
        warn sprintf("At %s for %s, cached %d items of which %d are empty\n",
                     $t, $species,
                     scalar keys %pfetch_cache,
                     scalar grep { !$_ } values %pfetch_cache);
    }

    # fetch cached info for the one we want,
    # also if filling cache considering the ones we will want next
    sub pfetch_md5 {
        my ($clone, $upcoming) = @_;
        my $cl_rname = $clone->seq_region_name;

        # Fetch a bunch at a time, so we can bulk up on the second round
        my $lim = 500;
        my $batch = 50;
        if (!exists $pfetch_cache{$cl_rname}) { # not pfetched
            my @want_acc = ($cl_rname);
            for (my $i=0; $i<@$upcoming && @want_acc < $lim && $i < 10*$lim; $i++) {
                my $rname = $upcoming->[$i]->seq_region_name;
                push @want_acc, $rname unless exists $pfetch_cache{$rname};
            }
            while (@want_acc) {
                my @batch = splice @want_acc, 0, $batch;
                @pfetch_cache{ @batch } = _pfetch_md5(@batch);
            }
        }
        if (!$pfetch_cache{$cl_rname}) { # pfetched, no match
            my @want_acc = ($cl_rname);
            push @want_acc, grep { $_ ne $cl_rname && !$pfetch_cache{$_} }
              keys %pfetch_cache;
            @want_acc = @want_acc[0..($batch-1)] if @want_acc > $batch;
            @pfetch_cache{ @want_acc } = _emblsva_md5(@want_acc);
        }

        return $pfetch_cache{$cl_rname};
    }
}

END {
    _cache_drop();
}


sub _pfetch_md5 {
    my (@acc) = @_;

    printf STDERR 'pfetch(%d): ', scalar @acc;

    open my $fh, '-|', qw( pfetch --md5 ), @acc
      or die "Pipe from pfetch: open failed ($!)";
    my @sum = <$fh>;
    print STDERR "done\n";
    close $fh
      or die "Pipe from pfetch: close failed ($!, $?)";
    die sprintf("pfetch fail: input count %s != output count %s\n",
                scalar @acc, scalar @sum) unless @acc == @sum;

    chomp @sum;
    my @bad = grep { ! m{^([a-f0-9]{32}|no match)$} } @sum;
    die "Bad output (@bad) from pfetch" if @bad;

    return map { $_ eq 'no match' ? '' : $_ } @sum;
}

sub _emblsva_md5 {
    my (@acc) = @_;

    ### From mca mail to Support 2012-11-05,
    #
    # When fetching from EMBL SVA we may use ENA
    #    http://www.ebi.ac.uk/ena/data/view/A00145.1,A00146.1,A00147.1&display=fasta
    # but it will not return suppressed items.
    #
    # Instead we bulk-fetch from EMBL-SVA, but will not hear if items
    # were suppressed
    #
    # Less recommended is dbfetch,
    #    http://www.ebi.ac.uk/Tools/dbfetch/dbfetch?db=emblsva&id=CU076058.19%2CCU633951.2&format=fasta&style=raw&Retrieve=Retrieve
    #
    # We are requested to run not more than three parallel threads.
    # No need to wait between queries.  We intend just one thread, but
    # have no lockout mechanism.

    printf STDERR 'embl-sva(%d): ', scalar @acc;

    my ($fh, $fn) = tempfile('sva.txt.XXXXXX', UNLINK => 1, TMPDIR => 1);
    print {$fh} map {"$_\n"} @acc
      or die "print tmpfile(list) $fn: $!";
    close $fh
      or die "close tmpfile(list) $fn: $!";

    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    $ua->env_proxy;
    $ua->agent('Anacode clone_dna.t '. $ua->_agent);

    my $response = $ua->post
      ('http://www.ebi.ac.uk/cgi-bin/sva/sva.pl',
       Content_Type => 'form-data',
       Content => [qw[ do_batch 1  format EMBLGZ  unload_batch Go!  batch_file ],
                   [ $fn ]]);

    die "EMBL-SVA fail: ".$response->status_line
      unless $response->is_success;

    print STDERR "done\n";


    # via tmpfile because SeqIO doesn't want in-memory data(?)
    ($fh, $fn) = tempfile('sva.gz.XXXXXX', UNLINK => 1, TMPDIR => 1);
    my $embl_gz = $response->decoded_content;
    my %err = gzip_excise(\$embl_gz);
    print {$fh} $embl_gz
      or die "print tmpfile(gz): $!";
    close $fh
      or die "close tmpfile(gz) $fn: $!";

    my %hit;
    %hit = embl_gz_md5s($fn, @acc) if $embl_gz ne '';
    # else nul result, eg. the only data was excised

    if (my @lost = grep { !$hit{$_} } @acc) {
        if ($embl_gz eq '' || gz_is_valid($fn)) {
            # Got valid data.  For missing items we have nowhere else
            # to look, set true-but-invalid result.
            @hit{@lost}=('!SVA') x @lost;
        } else {
            $File::Temp::KEEP_ALL = 1;
            die "Bad file $fn for something in (@lost)\n";
            # Fix it, else we cannot see the items after the one
            # causing the breakage
        }

#        my @got = sort(grep { $hit{$_} } keys %hit);
#        warn "SVA failed to return accessions (@lost),\n  got (@got)\n" if @lost;
    }

    my %out = (%hit, %err);

    delete @hit{@acc};
    my @spare = sort keys %hit;
    die "Spare SVA hits (@spare) remain" if @spare;

    return @out{@acc};
}


sub gz_is_valid {
    my ($fn) = @_;
    # is the .gz OK?
    open my $fh, '-|', zcat => $fn or die "zcat (for lost) fork: $!";
    my $junk = do { local $/ = undef; <$fh> };
    return close($fh);
}


# Workaround for bug
sub gzip_excise {
    my ($gzref, $hashref) = @_;
    my %out;

    while ($$gzref =~ s{(\A|\x01\x00)(ERROR.*?--\x0a)(\z|\x1f\x8b\x08\x00)}{$1$3}s) {
        my $err = $2;
        $err =~ s{\n}{\\n}g;
        warn "  ...excised $err\n";
        if ($err =~ m{ERROR: '([-_.0-9A-Za-f]+)'\n}) {
            my $acc = $1;
            warn "     for $acc\n";
            $out{$acc} = "!SVA: $err";
        }
    }

    return %out;
}


sub embl_gz_md5s {
    my ($fn) = @_;

    my %out;
    my $in = Bio::SeqIO->new(-format => 'EMBL', -file => "zcat $fn |");
    while (my $seq = $in->next_seq()) {
        my $acc = join '.', $seq->accession_number, $seq->version;
        unless ($seq->length) {
            warn "EMBL-SVA fetch: Skipping 0-length $acc\n";
            next;
        }
#        warn sprintf("EMBL-SVA: found %s len=%d\n", $acc, $seq->length);
        $out{$acc} = md5_hex( $seq->seq );
    }

    return %out;
}


main();

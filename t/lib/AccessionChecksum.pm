=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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

package AccessionChecksum;
use strict;
use warnings;

use GDBM_File;
use File::Temp 'tempfile';
use LWP::UserAgent;
use Digest::MD5 'md5_hex';
use Bio::SeqIO;


=head1 NAME

AccessionChecksum - obtain md5sum for ACC.SV by various means

=head1 DESCRIPTION

Fetch and cache C<md5sum(pfetch $foo)> by L<pfetch(1)> or from the
EMBL-SVA.

There is no automatic cache flushing, so do not use without the
C<.SV>.

=head1 CLASS METHOD

=head2 new($species)

The given species contributes only to the filename of the cache.

=cut

sub new {
    my ($pkg, $species) = @_;

    my $cachedir = Test::Otter->cachedir;
    my $fn = "$cachedir/pfetch-md5.cache=$species.gdbm";

    # Doing this in the hope of maintaining a sane open/close counter,
    # but without forcing our handler on the caller
    die "Refusing to bind GDBM without SIG{INT} handler"
      unless $SIG{INT};

    my %pfetch_cache;
    tie %pfetch_cache, 'GDBM_File', $fn, GDBM_WRCREAT, oct(664);
    # nb. GDBM doesn't store undef

    my $self = { _cache => \%pfetch_cache, _fn => $fn, _species => $species };
    bless $self, $pkg;

    $self->_summarise('start');

    return $self;
}


=head1 OBJECT METHODS

=cut

sub DESTROY {
    my ($self) = @_;
    $self->_summarise('end');
    untie %{ $self->{_cache} };
    return ();
}


sub _summarise {
    my ($self, $t) = @_;
    $self->_noise("At %s for %s, cached %d items of which %d are empty\n",
                  $t, $self->{_species},
                  scalar keys %{ $self->{_cache} },
                  scalar grep { !$_ } values %{ $self->{_cache} });
    return ();
}

sub _noise {
    my ($self, $fmt, @arg) = @_;
    return printf STDERR $fmt, @arg;
}


=head2 prefetch(\@upcoming)

For fetch efficiency, prefetch into the cache for the first few of the
given list of C<ACC.SV>.

This can die when fetching goes badly wrong in any of several ways.

=cut

my $ahead = 10;
my $batch = 50;
sub prefetch {
    my ($self, $upcoming) = @_;

    # pfetch a bunch at a time, so we can bulk up on the second round
    my @pre;
    for (my $i=0; $i<@$upcoming && @pre < $ahead*$batch && $i < $ahead*$ahead*$batch; $i++) {
        my $name = $upcoming->[$i];
        push @pre, $name unless defined $self->get_md5($name);
    }

    my @pfetch = @pre;
    while (@pfetch) {
        my @batch = splice @pfetch, 0, $batch;
        @{ $self->{_cache} }{ @batch } = $self->_pfetch_md5(@batch);
    }

    my @sva = grep { !$self->{_cache}{$_} } @pre;
    while (@sva) {
        my @batch = splice @sva, 0, $batch;
        @{ $self->{_cache} }{ @batch } = $self->_emblsva_md5(@batch);
    }

    return ();
}


=head2 get_md5($acc)

Return md5sum (or error string) for the C<ACC.SV> we want, or C<undef>
if no fetch attempt has been completed.

Error strings begin with C<!>.

=cut

sub get_md5 {
    my ($self, $acc) = @_;

    my $ret = $self->{_cache}{$acc};
    return defined $ret && $ret ne '' ? $ret : undef;
}


=head2 next_md5(\@acc)

Return C<($acc, $md5sum_or_error)> for the C<ACC.SV> given by C<shift
@acc>, calling L</prefetch> as necessary.

=cut

sub next_md5 {
    my ($self, $acc) = @_;
    my $next = $acc->[0];
    $self->prefetch($acc) unless defined $self->get_md5($next);
    shift @$acc;
    return ($next, $self->get_md5($next));
}


# Return 1:1 resulting @sum for input @acc.
sub _pfetch_md5 {
    my ($self, @acc) = @_;

    $self->_noise('pfetch(%d): ', scalar @acc);

    open my $fh, '-|', qw( pfetch --md5 ), @acc
      or die "Pipe from pfetch: open failed ($!)";
    my @sum = <$fh>;
    $self->_noise("done\n");

    close $fh
      or die "Pipe from pfetch: close failed ($!, $?)";
    die sprintf("pfetch fail: input count %s != output count %s (timeout?)\n",
                scalar @acc, scalar @sum) unless @acc == @sum;

    chomp @sum;
    my @bad = grep { ! m{^([a-f0-9]{32}|no match)$} } @sum;
    die "Bad output (@bad) from pfetch" if @bad;

    return map { $_ eq 'no match' ? '' : $_ } @sum;
}


# Return 1:1 resulting @sum for input @acc.
sub _emblsva_md5 {
    my ($self, @acc) = @_;

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

    $self->_noise('embl-sva(%d): ', scalar @acc);

    my ($fh, $fn) = tempfile('sva.txt.XXXXXX', UNLINK => 1, TMPDIR => 1);
    print {$fh} map {"$_\n"} @acc
      or die "print tmpfile(list) $fn: $!";
    close $fh
      or die "close tmpfile(list) $fn: $!";

    my $response = $self->_ua->post
      ('http://www.ebi.ac.uk/cgi-bin/sva/sva.pl',
       Content_Type => 'form-data',
       Content => [qw[ do_batch 1  format EMBLGZ  unload_batch Go!  batch_file ],
                   [ $fn ]]);

    die "EMBL-SVA fail: ".$response->status_line
      unless $response->is_success;

    $self->_noise("done\n");


    # via tmpfile because SeqIO doesn't want in-memory data(?)
    ($fh, $fn) = tempfile('sva.gz.XXXXXX', UNLINK => 1, TMPDIR => 1);
    my $embl_gz = $response->decoded_content;
    my %err = __gzip_excise(\$embl_gz);
    print {$fh} $embl_gz
      or die "print tmpfile(gz): $!";
    close $fh
      or die "close tmpfile(gz) $fn: $!";

    my %hit;
    %hit = __embl_gz_md5s($fn) if $embl_gz ne '';
    # else nul result, eg. the only data was excised

    if (my @lost = grep { !$hit{$_} } @acc) {
        if ($embl_gz eq '' || __gz_is_valid($fn)) {
            # Got no invalid data.  For missing items we have nowhere
            # else to look, set true-but-invalid result.
            @hit{@lost}=('!SVA') x @lost;
        } else {
            $File::Temp::KEEP_ALL = 1;
            die "Bad file $fn for something in (@lost) - preserving tmpfiles\n";
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


sub _ua {
    my ($self) = @_;
    return $self->{_ua} ||= do {
        my $ua = LWP::UserAgent->new;
        $ua->timeout(10);
        $ua->env_proxy;
        $ua->agent('Anacode AccessionChecksum.pm '. $ua->_agent);
        $ua;
    };
}


sub __gz_is_valid {
    my ($fn) = @_;
    # is the .gz OK?
    open my $fh, '-|', zcat => $fn or die "zcat (for lost) fork: $!";
    my $junk = do { local $/ = undef; <$fh> };
    return close($fh);
}


# Workaround for bug: text interspersed between (complete) gzip chunks
sub __gzip_excise {
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


sub __embl_gz_md5s {
    my ($fn) = @_;

    # Micromanage the lengths because (currently installed) Bio::SeqIO doesn't check.
    my @len;
    open my $fh, '-|', zcat => $fn
      or die "Failed to pipe from zcat $fn: $!";
    while (<$fh>) {
        next unless m{^ID\s+\S+};
        my ($bp) = m/^ID +.*; (\d+) BP\.\s*$/
          or die "No length on $_ (old file?)";
        push @len, $bp;
    }
    close $fh;


    my %out;
    my $in = Bio::SeqIO->new(-format => 'EMBL', -file => "zcat $fn |");
    while (my $seq = $in->next_seq()) {
        my $acc = join '.', $seq->accession_number, $seq->version;
        my $txt = $seq->seq;

        my $id_len = shift @len; # from the first pass
        my $txt_len = length($txt);
        if ($txt_len != $seq->length || $id_len != $txt_len) {
            # Partial fetch - the problem we set out to solve.
            # With the EMBL file at least we can see it.
            $File::Temp::KEEP_ALL = 1;
            die sprintf("Length mismatch on EMBL-SVA fetch '%s' (id:%d, txt:%d, api:%d) in file %s - preserving tmpfiles\n",
                        $acc, $id_len, $txt_len, $seq->length, $fn);
        }

        if (not $seq->length) {
            warn "EMBL-SVA fetch: Skipping 0-length $acc\n";
            next;
        }
#        else { $self->_noise("EMBL-SVA: found %s len=%d\n", $acc, $txt_len); }

        $out{$acc} = md5_hex( $txt );
    }

    return %out;
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;

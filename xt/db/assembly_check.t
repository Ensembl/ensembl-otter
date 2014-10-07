#! /software/bin/perl-5.12.2
use strict;
use warnings;

use Test::More;
use Test::Otter qw( ^db_or_skipall get_BOSDatasets diagdump );

use Try::Tiny;


=head1 DESCRIPTION

=head2 This script checks

=over 4

=item * assembly mapping segments in general (by SQL)

=item * the chromosome:contig:clone mappings (by SQL)

=item * chromosome mappings via API, where SQL shows any linkage

=back

=head2 This script does not check

=over 4

=item * The sequence of clones.  See F<slow/clone_dna.t>    TODO

=item * Equivalence of assemblies between loutre and pipe.  TODO

=back

=head1 CAVEATS

SQL tests are structured as SELECTs which return no rows on success.
This makes adding new tests simple, but has the obvious drawback that
an impossible constraint makes the test useless.  This is mitigated by
sharing SQL text where possible.

=head1 AUTHOR

mca@sanger.ac.uk

=cut


sub main {
    if (!@ARGV) {
        # species which pass
        push @ARGV,
          qw( rat gibbon opossum chimp wallaby gorilla platypus chicken
              mus_spretus dog tropicalis cat tomato marmoset medicago lemur
              sordaria tas_devil );

        # species which fail
@ARGV=();
        push @ARGV, qw( human mouse zebrafish pig );

        # restricted: nod_mouse
    }

    my @ds = get_BOSDatasets(@ARGV);


    ### Replace with backup-restored-hacked copy, for building the testcases
    #
    @ds = ();
    push @ds, Bio::Otter::SpeciesDat::DataSet->new
      (human_20140101 => {qw{ DBNAME mca_loutre_human_20140101 DBSPEC otterpipe2 DNA_DBSPEC otterlive READONLY 1 }});
    #
    ###

    my $maxrow = 2;

    my $FROM_ASM_A_CMP = q{  from
   seq_region asm
    join assembly a     on a.asm_seq_region_id = asm.seq_region_id
    join seq_region cmp on a.cmp_seq_region_id = cmp.seq_region_id
    join coord_system asmcs on asm.coord_system_id = asmcs.coord_system_id
    join coord_system cmpcs on cmp.coord_system_id = cmpcs.coord_system_id};

    my ($ASM_NAME, $CMP_NAME) =
      map { qq{ concat_ws(':', ${_}cs.name, ${_}cs.version, ${_}.name) } }
        qw( asm cmp );

    my %sql =
      ('assembly segment asm/cmp length: match && >= 0' => qq{
  select
   '>asm:name,seglen', $ASM_NAME, asm_end-asm_start+1 asm_len,
   '>cmp:name,seglen', $CMP_NAME, cmp_end-cmp_start+1 cmp_len,
   '>assembly_row', a.*
  $FROM_ASM_A_CMP
  where asm_end-asm_start+1 <> cmp_end-cmp_start+1
     or asm_end-asm_start+1 <= 0 },
       # where ori=-1 the lengths are still +ve
       # (almost always, and the rest look like a bad AGP loaded)

       (map {( "assembly.${_} side" => qq{
  select distinct
   '>asm:name,len,start,end', $ASM_NAME, asm.length, asm_start, asm_end,
   '>cmp:name,len,start,end', $CMP_NAME, cmp.length, cmp_start, cmp_end,
   '>ori', ori
  $FROM_ASM_A_CMP
  where (${_}_end > ${_}.length
      or ${_}_start < 1) } )} qw( asm cmp )),

       'contigs match their clone' => qq{
  select distinct
   '>asm:name,len', $ASM_NAME, asm.length,
   '>cmp:name',     $CMP_NAME
  $FROM_ASM_A_CMP
  where cmpcs.name = 'contig'
    and asmcs.name = 'clone'
    and (cmp.name <> concat_ws('.', asm.name, 1, asm.length)
      or asmcs.name <> 'clone'
      or a.asm_start <> 1 or a.cmp_start <> 1
      or a.asm_end <> asm.length
      or a.cmp_end <> asm.length
      or cmp.length <> asm.length
      or a.ori <> 1
        ) },

      );

    my %fuzz; # hardwired excuses for some non-exact assemblies
    $fuzz{mca_loutre_human_20140101} =
      { 'chr7-04:chr7-03' => 4267,
        'chr6-18:chr6-17' => 2000,
        'chr13-13:chr13-12' => 27069,
        'chr1-14:chr1-13' => 7962073 };

    plan tests => @ds * (2 + keys %sql);

    foreach my $ds (@ds) {
        my $dbc = $ds->otter_dba->dbc;
        my $dbh = $dbc->db_handle;
        my $dbname = $dbc->dbname;

        foreach my $qname (sort keys %sql) {
            my $R = $dbh->selectall_arrayref("$sql{$qname} limit $maxrow");

            local $TODO = "many things are broken";
            is(scalar @$R, 0, "$dbname: $qname")
              or diagdump(R => $R);
        }

        for my $dba ($ds->otter_dba, $ds->pipeline_dba) {
            my $name = $dba->dbc->dbname;

            subtest "$name by API" => sub {
                return try {
                    project_tt($dba, $fuzz{$name} || {});
                } catch {
                    fail 'Caught exception';
                    note $_;
                };
            };
        }
    }

    my $V = try {
        require Bio::EnsEMBL::ApiVersion; # since v59
        Bio::EnsEMBL::ApiVersion::software_version();
    } catch {
        require Bio::EnsEMBL::Registry;
        Bio::EnsEMBL::Registry::software_version(); # since v34 ?
    };
    note "e! API v$V";

    return ();
}


sub project_tt {
    my ($dba, $fuzzh) = @_;
    my $dbname = $dba->dbc->dbname;
    my $dbh = $dba->dbc->db_handle;
    my $SA = $dba->get_SliceAdaptor;

    # What current chromosomes do we have?
    my $chr = $dbh->selectcol_arrayref
      (q{ SELECT r.name
          FROM seq_region r
            JOIN coord_system cs using (coord_system_id)
          WHERE cs.name = 'chromosome'
            AND cs.version = 'Otter' });

    plan tests => scalar @$chr;

    foreach my $sr_name (@$chr) { SKIP: {
        # Get whole chromosome, no fuzzy
        my $slice = $SA->fetch_by_region
          (chromosome => $sr_name => undef, undef, undef, Otter => 1);
        if (!$slice) {
            fail("$dbname $sr_name: slice not found");
            next;
        }
        my $srid = $SA->get_seq_region_id($slice);

        # What does the assembly table say should be reachable?
        my @linked;
        foreach my $iter ([qw[ asm cmp forwards ]], [qw[ cmp asm backwards ]]) {
            my ($from, $to, $dir) = @$iter;
            my $linked = $dbh->selectall_arrayref
              (qq{ SELECT '$dir',
                    r.seq_region_id, r.name, cs.version,
                    sum(a.asm_end - a.asm_start + 1) nbase,
                    count(a.asm_end)                 nseg
                  FROM seq_region r
                   JOIN assembly a ON r.seq_region_id = a.${to}_seq_region_id
                   JOIN coord_system cs using (coord_system_id)
                  WHERE a.${from}_seq_region_id = ?
                    AND cs.name='chromosome'
                    AND cs.version not in ('OtterArchive')
                 -- to project to/from OtterArchive, first move to another cs
                  GROUP BY 1,2,3,4 }, {}, $srid);
            push @linked, @$linked;

        }
        if (!@linked && $dbname =~ /^pipe_/) {
            skip "$dbname.assembly shows no chromosomes linked to $sr_name", 1;
        } elsif (!@linked) {
            diag "no chromosomes linked to $sr_name, expected some";
        }

        my (@project_ok, @project_bad);
        foreach my $ln (@linked) {
            my ($dir, $to_srid, $to_name, $to_vsn, $nbase, $nseg) = @$ln;
            my $to_slice = $SA->fetch_by_seq_region_id($to_srid);

            my $proj = $slice->project_to_slice($to_slice);
            if (!@$proj) {
                # no segments, try the other way
                $proj = $to_slice->project_to_slice($slice);
                fail("Inverse projection $sr_name<-$to_name gave results!?")
                  if @$proj;
                # It shouldn't help.  If it did, we also see badproj
                # because this swapping code is not fully symmetrical
            }
            my ($to_nbase, $to_nseg, $badproj) = (0) x 3;
            foreach my $seg (@$proj) {
                $to_nbase += abs($seg->from_end - $seg->from_start) + 1;
                $to_nseg ++;
                my $got_to_srid = $SA->get_seq_region_id($seg->to_Slice);
                $badproj = $seg->to_Slice->display_id
                  if $to_srid != $got_to_srid;
            }

            my %projection =
              (from => $slice->display_id,
               to => $to_slice->display_id,
               direction => $dir,
               got_nbase => $to_nbase,
               got_nseg => $to_nseg,
               want_nbase => $nbase,
               expect_nseg => $nseg,
               badproj => $badproj);

            my $fuzzname = join ':', $sr_name, $to_name;
            my $pairfuzz = $fuzzh->{$fuzzname} || 0;

            my @bad;
            push @bad, 'badproj' if $badproj;
            push @bad, 'noseg' unless $to_nseg;
            my $nbase_diff = $to_nbase - $nbase;
            push @bad, "shortlen:$nbase_diff" unless
              ( !$to_nseg # already reported
                || abs($nbase_diff) <= $pairfuzz # match enough (all) bases
              );
            $projection{bad} = \@bad if @bad;
            my $binref = @bad ? \@project_bad : \@project_ok;
            push @$binref, \%projection;
        }
        my $n_ok = @project_ok;
        my $n_bad = @project_bad;
        ok($n_ok && !$n_bad,
           "$dbname $sr_name has projections ($n_ok good, $n_bad bad)") or
             diagdump(good => \@project_ok, bad => \@project_bad);
    } }

    return;
}

main();

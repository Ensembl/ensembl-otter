#! /software/bin/perl-5.12.2
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Test::More;
use Test::Otter qw( ^db_or_skipall get_BOSDatasets diagdump );

use Try::Tiny;


=head1 SYNOPSIS

 # default is to run on all datasets

 prove xt/db/assembly_check.t :: human mouse

 PROVE_DATASETS='human mouse' prove xt/db/assembly_check.t


=head1 DESCRIPTION

This test can run on all datasets (default), or those named in @ARGV
(not so convenient for L<prove(1)>), or those named in the
C<$PROVE_DATASETS> environment variable.

For each dataset (on both loutre and pipe), enumerate the
"interesting" pairs of C<seq_region>s linked via the C<assembly> table
and assert that one of

=over 2

=item 1. The projection API maps in both directions.

The number of segments and total bases returned should match the
assembly table.

=item 2. One or both C<seq_region>s are in C<chromosome:OtterArchive>
and therefore not expected to project correctly.

We treat this C<coord_system> like a never-purged trash folder.

It seems the assembly mapper currently (to v76) doesn't work well
where there is not a single source and destination on the
coord_systems involved.  Even when the C<assembly.mapping> is marked
with C<#> instead of C<|>.

Not sure whether it's a code bug or a data bug, just remember not to
step on it.

=item 3. There is something wrong with the assembly rows.

It should be possible to report this in the failure.

Not implemented - first see what's broken.

=back

should hold in every case.

Also there should be "interesting" chromosome:Otter#chromosome
mappings on loutre.


=head2 Interesting assembly groups

As defined in C<interesting_q()>.

=head2 Not checked

Clone to contig mapping is ignored.


=head1 OLD CHECKS

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
    my @ds_name = @_;
    @ds_name = split /\s+/, $ENV{PROVE_DATASETS}
      if !@ds_name && defined $ENV{PROVE_DATASETS};
    @ds_name = qw( ALL ) unless @ds_name;

    my @ds = get_BOSDatasets(grep { $_ ne 'TEST' } @ds_name);

    if (grep { $_ eq 'TEST' } @ds_name) {
        # Replace with backup-restored-hacked copy, for building the testcases
        push @ds, Bio::Otter::SpeciesDat::DataSet->new
          (human_20140101 => {qw{ DBNAME mca_loutre_human_20140101 DBSPEC otterpipe2 DNA_DBSPEC otterlive READONLY 1 }});
    }

    show_vsn();

    plan tests => 1 * @ds;
    foreach my $ds (@ds) {
        my $name = $ds->name;
        subtest $name => sub {
            plan tests => 3;
            note "In $name";

            foreach my $t ([ loutre => $ds->otter_dba ],
                           [ pipe => $ds->pipeline_dba ]) {

                my ($type, $dba) = @$t;
                my $dbh = $dba->dbc->db_handle;
                my @asmpairs = interesting_select($dbh);
                my $dbname = $dba->dbc->dbname;

                # Can we 1) map it 2) not care about it 3) explain the breakage?
                subtest "$name\[$type]=$dbname trilemma" => sub {
                    trilemma_tt($dba, \@asmpairs);
                };

                # Is everything connected which should be?
                subtest "$dbname is linked" => sub {
                    linkage_tt($dba, \@asmpairs);
                } if $type eq 'loutre';

            }
        };
    }

    return 0;
}


sub old_check_tt { # currently unused
    my ($ds) = @_;

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

    plan tests => scalar keys %sql;

    my $dbc = $ds->otter_dba->dbc;
    my $dbh = $dbc->db_handle;
    my $dbname = $dbc->dbname;

    foreach my $qname (sort keys %sql) {
        my $R = $dbh->selectall_arrayref("$sql{$qname} limit $maxrow");

        local $TODO = "many things are broken";
        is(scalar @$R, 0, "$dbname: $qname")
          or diagdump(R => $R);
    }

    return;
}

sub fuzz {
    my ($ds_name) = @_;

    my %fuzz; # hardwired excuses for some non-exact assemblies
    $fuzz{mca_loutre_human_20140101} =
      { 'chr7-04:chr7-03' => 4267,
        'chr6-18:chr6-17' => 2000,
        'chr13-13:chr13-12' => 27069,
        'chr1-14:chr1-13' => 7962073 };

    return $fuzz{$ds_name} || {};
}


sub trilemma_tt {
    my ($dba, $asmpairs) = @_;
    my $name = $dba->dbc->dbname;
    note "In $name";
    my $fuzzh = fuzz($name);
    # plan tests => variable

    my @no_project;
    foreach my $pair (@$asmpairs) {
        next unless $pair->col('nseg'); # no segments, nothing to project
        next if $pair->as_txt eq 'clone:-:<various> ~~ contig:none:<various>';
        my @trashy = $pair->is_trash;
        my $proj = try {
            local $TODO = @trashy ? "not expected to project (@trashy)" : undef;
            my $fuzz = $fuzzh->{ join ':', $pair->col(qw( asm_name cmp_name )) };
            $pair->lenfuzz($fuzz || 0);
            push @no_project, $pair
              unless can_project($dba, $pair) || $TODO;
        } catch {
            fail 'Caught exception on '.$pair->as_txt;
            note $_;
        };
    }

### do something to explain why.  further fail if we don't know?
#
#    foreach my $pair (@no_project) {
#        fail("no project: ".$pair->as_txt)
#    }

    return;
}


sub linkage_tt {
    my ($dba, $asmpairs) = @_;
    my $name = $dba->dbc->dbname;
    plan tests => 1;
    local $TODO = 'not implemented';
    return fail('how to figure out what should be linked?');
}


sub show_vsn {
    my $V = try {
        require Bio::EnsEMBL::ApiVersion; # since v59
        Bio::EnsEMBL::ApiVersion::software_version();
    } catch {
        require Bio::EnsEMBL::Registry;
        Bio::EnsEMBL::Registry::software_version(); # since v34 ?
    };
    note "e! API v$V";
    return;
}


sub interesting_q {
    return <<'SQL';
 SELECT
  asmcs.name, asmcs.version, if(asmcs.name in ('clone','contig'), '<various>', asm.name) asm_name,
  cmpcs.name, cmpcs.version, case
    when min(cmp.name) is null and max(cmp.name) is null then null
    when min(cmp.name) = max(cmp.name) then min(cmp.name)
    else '<various>' end cmp_name,
  sum(a.asm_end - a.asm_start + 1) nbase,
  count(a.asm_end)                 nseg,
  count(distinct cmp_seq_region_id) n_cmp_region,
  min(asm_start), max(asm_end),
  min(cmp_start), max(cmp_end)
 FROM seq_region asm
   JOIN coord_system asmcs on asm.coord_system_id=asmcs.coord_system_id
   LEFT JOIN assembly a ON asm.seq_region_id = a.asm_seq_region_id
   LEFT JOIN seq_region cmp on cmp.seq_region_id = a.cmp_seq_region_id
   LEFT JOIN coord_system cmpcs on cmp.coord_system_id=cmpcs.coord_system_id
 GROUP BY 1,2,3,4,5
 ORDER BY 1,2,4,5,length(asm.name),3,6
SQL
}

sub interesting_select {
    my ($dbh) = @_;
    my $rows = $dbh->selectall_arrayref(interesting_q());
    return map { _Interesting->new($_) } @$rows;
}

sub can_project {
    my ($dba, $pair) = @_;
    my $SA = $dba->get_SliceAdaptor;
    my $pairname = $pair->as_txt;

    # Get slices for both regions
    my ($asm, $cmp) = map { $pair->fetch_by_region($_ => $SA) } qw{ asm cmp };

    my %proj; # the segments
    my %proj_to; # expected destination

    # $cmp, and so $rev, may be undef if '<various>'
    if (defined $cmp) {
        @proj{qw{ fwd rev }} =
          ($asm->project_to_slice($cmp),
           $cmp->project_to_slice($asm));
        @proj_to{qw{ fwd_srid rev_srid }} =
          map { $SA->get_seq_region_id($_) } ($cmp, $asm);
    } else {
        my @to_cs = undef_dash( $pair->col('cmpcs.name', 'cmpcs.version') );
        $proj{fwd} = $asm->project(@to_cs);
        $proj{rev} = undef;
        $proj_to{fwd_cs} = join ':', @to_cs;
    }

    my $ok = 1;
    foreach my $dir (sort keys %proj) { SKIP: {
        skip "no $dir projection for $pairname", 1 unless defined $proj{$dir};

        $ok = 0 unless check_projected($dba, $pair, $dir, $proj{$dir}, \%proj_to);
    } }

    return $ok;
}

sub check_projected {
    my ($dba, $pair, $dir, $proj, $proj_to) = @_;
    my $dbname = $dba->dbc->dbname;
    my $SA = $dba->get_SliceAdaptor;
    my $pairname = $pair->as_txt;

    my ($to_nbase, $to_nseg, $badproj) = (0) x 3;
    for (my $i=0; $i < @$proj; $i++) {
        my $seg = $proj->[$i];
        $to_nbase += abs($seg->from_end - $seg->from_start) + 1;
        $to_nseg ++;
        if (my $to_srid = $proj_to->{$dir.'_srid'}) {
            my $got_to_srid = $SA->get_seq_region_id($seg->to_Slice);
            $badproj ||= "#$i: ".$seg->to_Slice->display_id
              if $to_srid != $got_to_srid;
        } else {
            my $got_cs = $seg->to_Slice->coord_system;
            $got_cs = join ':', undef_dash($got_cs->name, $got_cs->version);
            $badproj ||= "#$i: ".$seg->to_Slice->display_id
              if $proj_to->{$dir.'_cs'} ne $got_cs;
        }
    }

    # Now we know how it projects OK.  Summarise.
    my %projection =
      (name => "$pairname ($dir)",
       got_nbase => $to_nbase,
       got_nseg => $to_nseg,
       want_nbase => $pair->col('nbase'),
       want_nseg => $pair->col('nseg'));
    $projection{badproj} = $badproj if $badproj;

    my @bad;
    push @bad, 'badproj' if $badproj;
    push @bad, 'noseg' unless $to_nseg;
    my $nbase_diff = $to_nbase - $projection{want_nbase};
    my $nseg_diff  = $to_nseg  - $projection{want_nseg};
    if ($to_nseg) {
        push @bad, "shortlen:$nbase_diff" unless abs($nbase_diff) <= $pair->lenfuzz;
        push @bad, "nseg:$nseg_diff"      unless $nseg_diff == 0;
    }
    $projection{bad} = \@bad if @bad;

    if ("@bad" eq 'noseg') {
        # spare the noise for an outright non-projection
        fail("$dbname $pairname projects $dir to no segments");
        return 0;
    } elsif (ok(!@bad, "$dbname $pairname projects $dir")) {
        # good
        return 1;
    } else {
        diagdump(projection => \%projection);
        return 0;
    }
}

sub undef_dash {
    my @in = @_;
    my @out = map { defined $_ ? $_ : '-' } @in;
    die unless wantarray;
    return @out;
}


exit main(@ARGV);



package _Interesting; # a blessed SQL row

my %fld; ## no critic (ControlStructures::ProhibitUnreachableCode)
sub new {
    my ($pkg, $row) = @_;
    $pkg->_classinit unless keys %fld;
    push @$row, {}; # _config
    return bless $row, $pkg;
}

sub _classinit {
    my @f =
      qw( asmcs.name asmcs.version  asm_name
          cmpcs.name cmpcs.version  cmp_name
          nbase nseg n_cmp_region
          min_asm_start max_asm_end
          min_cmp_start max_cmp_end
          _config );
    @fld{@f} = (0 .. $#f);
    return;
}

sub col {
    my ($self, @field) = @_;
    my @x = @fld{@field};
    die "Unknown field(s)  (@field) => (@x)" if grep {!defined} @x;
    return $self->[$x[0]] if 1==@x;
    die 'wantarray' unless wantarray;
    return @{$self}[@x];
}

# post-SQL-fetch configured nbase fuzz
sub lenfuzz {
    my ($self, @set) = @_;
    ($self->col('_config')->{lenfuzz}) = @set if @set;
    return $self->col('_config')->{lenfuzz};
}

sub _CVR {
    my ($self, $side) = @_;
    return $self->col("${side}cs.name", "${side}cs.version", "${side}_name");
}

sub name {
    my ($self, $side, $CVR) = @_;
    $CVR ||= 'CVR';
    my %name;
    @name{qw{ C V R }} = $self->_CVR($side);
    my @out = map { defined $_ ? $_ : '-' }
      @name{ split //, $CVR };
    return join ':', @out;
}


sub _Trash_cs {
    return qw( chromosome:OtterArchive );
    # Things in here may not map correctly, but we don't care.
    # To project to/from OtterArchive, first move to another cs.
}

sub is_trash {
    my ($self) = @_;
    my @out;
    foreach my $side (qw( asm cmp )) {
        my $coord_system = $self->name($side, 'CV');
        push @out, $side if grep { $_ eq $coord_system } _Trash_cs();
    }
    return @out;
}


sub fetch_by_region {
    my ($self, $side, $slice_adaptor) = @_;
    my ($C, $V, $R) = $self->_CVR($side);
    my $slice = $slice_adaptor->fetch_by_region
      ($C, $R, undef, undef, undef, $V, 1);
    if (!$slice) {
        my $dbname = $slice_adaptor->dbc->dbname;
        my $name = $self->name($side);
        die "$dbname: region $name not found"
          unless $R eq '<various>' && $side eq 'cmp'; # e.g. chromosome=>contigs
    }
    return $slice;
}

sub as_txt {
    my ($self) = @_;
    my ($asm, $cmp) = ($self->name('asm'), $self->name('cmp'));
    return "$asm ~~ $cmp";
}

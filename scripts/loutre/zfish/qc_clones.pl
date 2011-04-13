#!/usr/local/bin/perl -w
#
# collects all qc checked clones

#BEGIN {
#    unshift(@INC, "$ENV{'BADGER'}/bin");
#    unshift(@INC, "."); 
#}

use strict;
use WrapDBI;

my $dbi;
my @chromoX;



# TEST DB CONNECTION
eval {
  $dbi = WrapDBI->connect('reports',{RaiseError => 1});
  $dbi->{autocommit} = 0;
};

if($@) {
  die"ERROR: Unable to connect to oracle.$@\n";
}

# prepare oracle query
my $sql = $dbi->prepare(qq[
    select c.clonename,
    s.accession,
    s.sv,
    ps.status
    from clone c,
    clone_sequence cs,
    sequence s,
    clone_project cp,
    project_status ps
    where c.speciesname = 'Zebrafish'
    and c.clonename = cs.clonename
    and cs.is_current = '1'
    and cs.id_sequence = s.id_sequence
    and c.clonename = cp.clonename
    and cp.projectname = ps.projectname
    and ps.status in
	(35 /* QC Checked */,
	44 /* Pooled Clone Finished */,
	48 /* Indexed Clone Finished */)
    order by c.clonename
]);


# execute for each command line query
$sql->execute();
while (my @row = $sql->fetchrow_array) {
    print join "\t", @row, "\n";
}

print"\n";



# hasta luego
END {

  $dbi->disconnect() if $dbi;

}

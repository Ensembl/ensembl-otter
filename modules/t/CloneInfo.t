
use lib 't';

BEGIN { $| = 1; print "1..8\n"; }
my $loaded = 0;
END {print "not ok 1\n" unless $loaded;}

use Bio::Otter::CloneInfo;
use Bio::Otter::Author;

$loaded = 1;

my $name = "michele";
my $mail = "michele\@sanger.ac.uk";

my $author = new Bio::Otter::Author(-name => $name,
                                    -email => $mail);

print "ok 1\n";

my $cloneinfo = new Bio::Otter::CloneInfo(-clone_id  => 1,
	                                  -author    => $author,
                                          -timestamp => 100,
                                          -is_active => 1,
                                          -remark    => 'This is a clone info object',
                                          -source    => 'SANGER'); 


print "ok 2\n";

my $newauthor = $cloneinfo->author;

if (defined($newauthor)) {
  print "ok 3\n";
  print $newauthor->name . " " . $newauthor->email . "\n";
} else {
 print "not ok 3\n";
}


if (defined($cloneinfo->clone_id)) {
  print "ok 4\n";
  print $cloneinfo->clone_id . "\n";
} else {
 print "not ok 4\n";
}


if (defined($cloneinfo->timestamp)) {
  print "ok 5\n";
  print $cloneinfo->timestamp . "\n";
} else {
 print "not ok 5\n";
}


if (defined($cloneinfo->is_active)) {
  print "ok 6\n";
  print $cloneinfo->is_active . "\n";
} else {
 print "not ok 6\n";
}

if (defined($cloneinfo->remark)) {
  print "ok 7\n";
  print $cloneinfo->remark . "\n";

} else {
 print "not ok 7\n";
}

if (defined($cloneinfo->source)) {
  print "ok 8\n";
  print $cloneinfo->source . "\n";
} else {
 print "not ok 8\n";
}


use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 10;}

use Bio::Otter::Author;

ok(1);

my $name1 = "michele";
my $name2 = "james";

my $mail = "michele\@sanger.ac.uk";

my $author = new Bio::Otter::Author(-dbID  => 1,
				     -name => $name1,
				     -email => $mail);
my $author2 = new Bio::Otter::Author(-dbID  => 2,
				     -name => $name2,
				     -email => $mail);


ok(2);

ok($author->dbID == 1);
ok($author->name eq "michele");
ok($author->email eq "michele\@sanger.ac.uk");

print $author->toString . "\n";

$author->dbID(2);
$author->name("searle");
$author->email("searle\@sanger.ac.uk");

ok($author->dbID == 2);
ok($author->name eq "searle");
ok($author->email eq "searle\@sanger.ac.uk");

print $author->toString . "\n";

ok($author->equals($author));

ok ($author->equals($author2) == 0);

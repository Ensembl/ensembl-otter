
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 7;}

use Bio::Otter::CloneLock;
use Bio::Otter::Author;

my $name = "michele";
my $mail = "michele\@sanger.ac.uk";

my $author = new Bio::Otter::Author(-name => $name,
                                    -email => $mail);

ok(1);

my $clonelock = new Bio::Otter::CloneLock(-id        => 'AC003663',
                                          -version   => 1,
	                                  -author    => $author,
                                          -timestamp => 100);

ok(2);

ok($clonelock->author);

ok($clonelock->id eq 'AC003663');
ok($clonelock->timestamp == 100);
ok($clonelock->version == 1);
ok($clonelock->type eq 'CLONE');

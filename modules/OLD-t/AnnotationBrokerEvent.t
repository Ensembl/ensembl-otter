
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 5;}

use Bio::Otter::AnnotationBroker::Event;
use Bio::Otter::AnnotatedGene;


my $gene = Bio::Otter::AnnotatedGene->new();


my $ngene = Bio::Otter::AnnotatedGene->new();

ok(1);

my $event = Bio::Otter::AnnotationBroker::Event->new( -type => 'modified',
						-old => $gene,
						-new => $ngene);

ok(2);

ok($event->type eq 'modified');
ok($event->old_gene == $gene);
ok($event->new_gene == $ngene);


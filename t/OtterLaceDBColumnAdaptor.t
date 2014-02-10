#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use Bio::Otter::Lace::Source::Collection;
use Bio::Otter::Lace::Source::Item::Column;

use Test::Otter qw( ^data_dir_or_skipall ); # also finds test libraries
use OtterTest::DB;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my $adaptor_module;
BEGIN {
      $adaptor_module = 'Bio::Otter::Lace::DB::ColumnAdaptor';
      use_ok($adaptor_module);
}

critic_module_ok($adaptor_module);

my $test_db = OtterTest::DB->new;
my $ca = new_ok($adaptor_module => [ $test_db->dbh ]);

my @col;
my @exp = (
    { name => 'Test_col_one',   selected => 1     },
    { name => 'Test_col_two',   selected => undef },
    { name => 'Test_col_three', selected => undef },
    );

foreach my $i ( 0..$#exp ) {
    $col[$i] = Bio::Otter::Lace::Source::Item::Column->new;
    $col[$i]->name(    $exp[$i]->{name});
    $col[$i]->selected($exp[$i]->{selected});

    ok($ca->store_Column_state($col[$i]), "store $i");
    is($col[$i]->is_stored, 1, "is_stored $i");
}

my @sub_exp = @exp[ 0..($#exp - 1) ];

my $collection = setup_collection( map { $_->{name} } @sub_exp );
ok($ca->fetch_ColumnCollection_state($collection), 'fetch_ColumnCollection_state');

test_collection($collection, \@sub_exp, 'fetched Collection');

my @f_col = $collection->list_Columns;
$f_col[1]->selected(   $sub_exp[1]->{selected} = 1);
$f_col[1]->gff_file(   $sub_exp[1]->{gff_file} = '/my/test/file');
$f_col[1]->process_gff($sub_exp[1]->{process_gff} = 1);

ok($ca->store_ColumnCollection_state($collection), 'store_ColumnCollection_state');

my $collection2 = setup_collection( map { $_->{name} } @sub_exp );
ok($ca->fetch_ColumnCollection_state($collection2), 'fetch_ColumnCollection_state again');
test_collection($collection2, \@sub_exp, 'fetched Collection again');

ok($ca->update_for_filter_get($f_col[0]->name,
                              $sub_exp[0]->{gff_file} = '/file/updated',
                              $sub_exp[0]->{process_gff} = 0             ), 'update_for_filter_get');
$collection2 = setup_collection( map { $_->{name} } @sub_exp );
ok($ca->fetch_ColumnCollection_state($collection2), 'fetch_ColumnCollection_state post-update');

test_collection($collection2, \@sub_exp, 'fetched Collection post-update');

# RT380721
my @super_exp = @exp;
splice(@super_exp, 1, 0, (
           { name => 'Test_inserted_after_store_1', selected => 1 },
           { name => 'Test_inserted_after_store_2', selected => undef },
       ) );
my $collection3 = setup_collection(  map { $_->{name} } @super_exp );
$collection3->get_Item_by_name('Test_inserted_after_store_1')->selected(1);
ok($ca->fetch_ColumnCollection_state($collection3), 'fetch_ColumnCollection_state pre-store RT380721');
test_collection($collection3, \@super_exp, 'fetched Collection pre-store RT380721');
ok($ca->store_ColumnCollection_state($collection3), 'store_ColumnCollection_state RT380721');
ok($ca->fetch_ColumnCollection_state($collection3), 'fetch_ColumnCollection_state post-store RT380721');
test_collection($collection3, \@super_exp, 'fetched Collection post-store RT380721');

done_testing;

sub setup_collection {
    my (@names) = @_;
    my $coll = Bio::Otter::Lace::Source::Collection->new;
    foreach my $n (@names) {
        my $col = Bio::Otter::Lace::Source::Item::Column->new;
        $col->name($n);
        $coll->add_Item($col);
    }
    return $coll;
}

sub test_collection {
    my ($coll, $exp, $tname) = @_;
    subtest $tname => sub {
        my @c_col = $coll->list_Columns;
        is(scalar(@c_col), scalar(@$exp), 'n_Columns');
        foreach my $i (0..$#{$exp}) {
            foreach my $a (qw( name selected gff_file process_gff )) {
                is($c_col[$i]->$a(), $exp->[$i]->{$a}, "$a $i");
            }
        }
        done_testing;
    };
    return;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF

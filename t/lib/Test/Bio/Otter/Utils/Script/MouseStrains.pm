package Test::Bio::Otter::Utils::Script::MouseStrains;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes { return; } # none

sub setup : Tests(setup) {
    my $test = shift;
    $test->SUPER::setup;
    return;
}

sub codes : Test(3) {
    my $test = shift;
    my $ms = $test->our_object;

    my $old_codes = $ms->old_codes;
    my $new_codes = $ms->new_codes;

    my $n_old = scalar(@$old_codes);
    my $n_new = scalar(@$new_codes);

    ok($n_old > 1, 'have more than 1 old_codes');
    ok($n_new > 1, 'have more than 1 new_codes');

    ok($n_old == $n_new, 'counts match');

    note('Count: ', $n_old);
    return;
}

sub consistent : Test(1) {
    my $test = shift;
    my $ms = $test->our_object;

    my @old_codes = sort @{ $ms->old_codes };
    my @mapped_codes = sort map {
        my $o1 = $ms->by_old_code($_);
        my $o2 = $ms->by_new_code($o1->{new_code});
        $o2->{old_code};
    } @old_codes;

    cmp_deeply(\@mapped_codes, \@old_codes, 'two-way map');

    note('Count: ', scalar @mapped_codes);
    return;
}

sub unique : Test(4) {
    my $test = shift;
    foreach my $field ( qw{ old_code new_code strain_name grit_db_name } ) {
        $test->_unique($field);
    }
    return;
}

sub _unique {
    my ($test, $field) = @_;
    my $ms = $test->our_object;

    my @new_codes = @{ $ms->new_codes };
    my %map = map { $ms->by_code($_)->{$field} => 1 } @new_codes;

    is(scalar(keys(%map)), scalar(@new_codes), "'$field' is unique");

    note('Count: ', scalar(keys(%map)));
    return;
}

sub dataset_name : Test(1) {
    my ($test) = @_;
    my $ms = $test->our_object;

    is($ms->dataset_name_by_code('C57'), 'mouse-C57BL-6NJ', 'dataset_name_by_code');
    return;
}

sub dataset_names : Test(1) {
    my ($test) = @_;
    my $ms = $test->our_object;

    foreach my $nc (sort @{$ms->new_codes}) {
        note($nc, ' => ', $ms->old_dataset_name_by_code($nc),
                  ' => ', $ms->dataset_name_by_code($nc));
    }

    pass('dataset_names');
    return;
}

1;

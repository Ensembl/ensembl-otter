=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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

package Test::Bio::Otter::Utils::Script::MouseStrains;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes { return; } # none

sub setup : Tests(setup) {
    my $test = shift;
    $test->SUPER::setup;
    return;
}

sub all : Test(3) {
    my $test = shift;
    my $ms = $test->our_object;

    can_ok $ms, 'all';
    my $all =  $ms->all;
    my $n_all = scalar(@$all);

    ok($n_all > 1, '...have more than 1 entry');
    isa_ok($all->[0], 'Bio::Otter::Utils::Script::MouseStrain', '...first is correct type');

    return;
}

sub codes : Test(5) {
    my $test = shift;
    my $ms = $test->our_object;

    can_ok $ms, 'old_codes';
    can_ok $ms, 'new_codes';

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
        my $o2 = $ms->by_new_code($o1->new_code);
        $o2->old_code;
    } @old_codes;

    cmp_deeply(\@mapped_codes, \@old_codes, 'two-way map');

    note('Count: ', scalar @mapped_codes);
    return;
}

sub unique : Test(4) {
    my $test = shift;
    foreach my $field ( qw{ old_code strain_name grit_db_name } ) {
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

sub dataset_name : Test(2) {
    my ($test) = @_;
    my $ms = $test->our_object;

    my $c57 = $ms->by_code('C57');
    is($c57->dataset_name,     'mouse-C57BL-6NJ', 'dataset_name');
    is($c57->old_dataset_name, 'mus_C57',         'old_dataset_name');
    return;
}

sub dataset_names : Test(1) {
    my ($test) = @_;
    my $ms = $test->our_object;

    foreach my $nc (sort @{$ms->new_codes}) {
        my $s = $ms->by_code($nc);
        note($nc, ' => ', $s->old_dataset_name,
                  ' => ', $s->dataset_name
            );
    }

    pass('dataset_names');
    return;
}

sub db_name : Test(4) {
    my ($test) = @_;
    my $ms = $test->our_object;
    my $c57 = $ms->by_code('C57');

    can_ok $c57, 'db_name';
    is($c57->db_name,                'loutre_mus_r_c57', '...C57 name ok');
    is($c57->db_name('pipe'),        'pipe_mus_r_c57',   '...C57 pipe name ok');
    is($ms->by_code('LPJ')->db_name, 'loutre_mus_r_apj', '...LPJ name ok');
    return;
}

1;

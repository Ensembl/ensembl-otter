=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Test::Bio::Otter::Utils::CacheByName;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes { return; } # none

sub setup : Tests(setup) {
    my $test = shift;
    $test->SUPER::setup;

    my $cbn = $test->our_object;
    foreach my $key ( qw( A B C ) ) {
        my $obj = _new_test_object($key);
        $cbn->set($obj);
    }
    return;
}

sub test_set : Tests {             # set() is a Test::Deep sub
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'set';

    my $x1 = _new_test_object('X');
    ok($cbn->set($x1), '...and succeeds');
    _cmp_contents($cbn, [qw( A B C X )], '...cache okay');

    # plain old set() replaces silently
    my $x2 = _new_test_object('X');
    ok($cbn->set($x2), '...and can replace');
    _cmp_contents($cbn, [qw( A B C X )], '...cache still okay');
    isnt($cbn->get('X'), $x1, '...previous replaced (not prev)');
    is(  $cbn->get('X'), $x2, '...previous replaced (is this)');

    return;
}

{
    my ($_nu_sub_called, $_nu_sub_obj, $_nu_sub_name, $_nu_sub_retval);

    sub _not_unique {
        my ($obj, $name) = @_;

        $_nu_sub_called = 1;
        $_nu_sub_obj    = $obj;
        $_nu_sub_name   = $name;

        return $_nu_sub_retval;
    }

    sub _not_unique_reset {
        my ($retval) = @_;

        $_nu_sub_called = undef;
        $_nu_sub_obj    = undef;
        $_nu_sub_name   = undef;

        $_nu_sub_retval = $retval;

        return;
    }

    sub test_set_not_unique_sub : Tests {
        my $test = shift;
        my $cbn  = $test->our_object;
        can_ok $cbn, 'set';

        _not_unique_reset(undef);
        my $x1 = _new_test_object('X');
        ok($cbn->set($x1, \&_not_unique), '...and succeeds with not_unique_sub');
        _cmp_contents($cbn, [qw( A B C X )], '...  cache okay');
        is($_nu_sub_called, undef, '...  not_unique_sub not called');

        _not_unique_reset(undef);
        my $x2 = _new_test_object('X');
        ok(not(defined($cbn->set($x2, \&_not_unique))), '...and fails on duplicate with not_unique_sub');
        _cmp_contents($cbn, [qw( A B C X )], '...  cache okay');
        ok($_nu_sub_called,     '...  not_unique_sub called');
        is($_nu_sub_obj,  $x2,  '...  not_unique_sub passed correct object');
        is($_nu_sub_name, 'X',  '...  not_unique_sub passed correct name');
        is(  $cbn->get('X'), $x1, '...  previous not replaced (is prev)');
        isnt($cbn->get('X'), $x2, '...  previous not replaced (not this)');

        _not_unique_reset(1);   # permit replacement
        ok($cbn->set($x2, \&_not_unique), '...and replaces on duplicate when permitted by not_unique_sub');
        _cmp_contents($cbn, [qw( A B C X )], '...  cache okay');
        ok($_nu_sub_called,     '...  not_unique_sub called');
        is($_nu_sub_obj,  $x2,  '...  not_unique_sub passed correct object');
        is($_nu_sub_name, 'X',  '...  not_unique_sub passed correct name');
        isnt($cbn->get('X'), $x1, '...  previous replaced (not prev)');
        is(  $cbn->get('X'), $x2, '...  previous replaced (is this)');

        return;
    }
}

sub get : Tests {
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'get';

    my $obj = $cbn->get('B');
    ok($obj, '...and returns an object for a known key');
    _cmp_test_object($obj, 'B', '...  object okay');

    $obj = $cbn->get('X');
    ok(not(defined($obj)), '...and returns undef for an unknown key');

    return;
}

sub get_or_new : Tests {
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'get_or_new';

    my $maker = sub {
        my ($name) = @_;
        return _new_test_object($name);
    };

    my $existing = $cbn->get('C');
    my $try = $cbn->get_or_new('C', $maker);
    is($try, $existing, '...and returns existing');

    my $new = $cbn->get_or_new('Y', $maker);
    ok($new, '...and makes new');
    _cmp_test_object($new, 'Y', '...  object okay');
    _cmp_contents($cbn, [qw( A B C Y )], '...  cache okay');

    return;
}

sub get_or_this : Tests {
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'get_or_this';

    my $existing = $cbn->get('C');
    my $try = $cbn->get_or_this($existing);
    is($try, $existing, '... and returns existing');

    my $zed = _new_test_object('Z');
    my $got = $cbn->get_or_this($zed);
    is ($got, $zed, '... and adds this if not found');
    _cmp_contents($cbn, [qw( A B C Z )], '...  cache okay');

    return;
}

sub delete : Tests {
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'delete';

    my $deleted = $cbn->delete('C');
    ok($deleted, '...and delete returns something');
    _cmp_test_object($deleted, 'C', '... deleted object');
    _cmp_contents($cbn, [qw( A B )], '...  cache okay');

    my $not_there = $cbn->delete('C');
    ok(not(defined($not_there)), '...and delete returns undef if not there');
    _cmp_contents($cbn, [qw( A B )], '...  cache still okay');

    return;
}

sub delete_object : Tests {
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'delete_object';

    my $existing = $cbn->get('A');
    my $deleted = $cbn->delete_object($existing);
    ok($deleted, '...and delete returns something');
    is($deleted, $existing, '... deleted object matches');
    _cmp_contents($cbn, [qw( B C )], '...  cache okay');

    my $not_there = $cbn->delete_object($existing);
    ok(not(defined($not_there)), '...and delete returns undef if not there');
    _cmp_contents($cbn, [qw( B C )], '...  cache still okay');

    return;
}

sub names : Tests {
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'names';
    cmp_bag([$cbn->names], [qw( A B C )], '...and names match');
    return;
}

sub objects : Tests {
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'objects';
    my @objects = $cbn->objects;
    cmp_bag([map { $_->value } @objects],
            [qw( =A= =B= =C= )], '...and object values match');
    subtest '...isa for objects' => sub {
        foreach my $obj ( @objects ) {
            isa_ok($obj, 'CacheByName::TestObject');
        }
    };
    return;
}

sub empty : Tests {
    my $test = shift;
    my $cbn  = $test->our_object;
    can_ok $cbn, 'empty';
    $cbn->empty;
    _cmp_contents($cbn, [], '...and empties the cache');
    return;
}

sub alt_name_accessor : Tests {
    my $test = shift;

    my $cbn = Bio::Otter::Utils::CacheByName->new('alt_name');
    _cmp_contents($cbn, [], 'starts empty');

    foreach my $key ( qw( A B C ) ) {
        my $obj = CacheByName::TestObjectAltName->new($key, "=${key}=");
        $cbn->set($obj);
    }
    _cmp_contents($cbn, [qw( A B C )], 'set three');

    my $a = $cbn->get('A');
    $cbn->delete_object($a);
    _cmp_contents($cbn, [qw( B C )], 'delete one');

    my $existing = $cbn->get('C');
    my $try = $cbn->get_or_this($existing);
    is($try, $existing, 'get_or_this returns existing');

    my $zed = CacheByName::TestObjectAltName->new('Z', "=Z=");
    my $got = $cbn->get_or_this($zed);
    is ($got, $zed, 'get_or_this adds this if not found');
    _cmp_contents($cbn, [qw( B C Z )], 'cache okay');

    return;
}

sub _cmp_test_object {
    my ($got, $want, $what) = @_;
    subtest $what => sub {
        is($got->name,  $want,       'name');
        is($got->value, "=${want}=", 'value');
    };
    return;
}

sub _cmp_contents {
    my ($got, $want, $what) = @_;
    subtest $what => sub {
        cmp_bag([$got->names], $want, 'names');
        cmp_bag([map { $_->value } $got->objects],
                [map { "=$_=" } @$want],
                'object values');
    };
    return;
}

sub _new_test_object {
    my ($name) = @_;
    my $value = "=${name}=";
    return CacheByName::TestObject->new($name, $value);
}

package CacheByName::TestObject;

sub new {
    my ($class, $name, $value) = @_;
    return bless {
        name  => $name,
        value => $value,
    }, $class;
}

sub name {
    my ($self, @args) = @_;
    ($self->{'name'}) = @args if @args;
    my $name = $self->{'name'};
    return $name;
}

sub value {
    my ($self, @args) = @_;
    ($self->{'value'}) = @args if @args;
    my $value = $self->{'value'};
    return $value;
}

package CacheByName::TestObjectAltName;

use base 'CacheByName::TestObject';

sub name {
    die "Shouldn't be calling name() on me";
}

sub alt_name {
    my ($self, @args) = @_;
    return $self->SUPER::name(@args);
}

1;

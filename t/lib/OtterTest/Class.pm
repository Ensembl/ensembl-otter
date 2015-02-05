package OtterTest::Class;

use Test::Class::Most           # autmogically becomes our parent
    is_abstract => 1,
    attributes  => our_object;

use parent 'Class::Data::Inheritable';

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

BEGIN {
    __PACKAGE__->mk_classdata('class');
    __PACKAGE__->mk_classdata('run_all');
}

{
    my %no_run_tests;

    sub import {
        my ($class, %args) = @_;
        if (delete $args{no_run_test}) {
            my $caller = caller;
            $no_run_tests{$class} = 1;
        }
        return;
    }

    sub _test_classes {
        my $class = shift;
        my @test_classes = Test::Class::_test_classes($class);
        return @test_classes if __PACKAGE__->run_all;
        return grep { not $no_run_tests{$_} } @test_classes;
    }

    sub runtests {
        my @tests = @_;
        if (@tests == 1 && !ref($tests[0])) {
            my $base_class = shift @tests;
            @tests = _test_classes( $base_class ); # use my version
        }
        return Test::Class::runtests(@tests);
    }

    INIT {
        __PACKAGE__->runtests;
    }
}

sub is_abstract {
    my $test = shift;
    return Test::Class::Most->is_abstract($test);
}

sub startup : Tests(startup => 1) {
    my $test  = shift;
    return 'abstract base class' if $test->is_abstract;

    ( my $class = ref $test ) =~ s/^Test:://;

    use_ok $class or die;
    $test->class($class);

    return;
}

sub setup : Tests(setup) {
    my $test = shift;
    return if $test->is_abstract;

    my $class = $test->class;
    $test->our_object($class->new);
    return;
}

# sub attributes { return undef }

sub _critic : Test(1) {
    my $test = shift;
    return 'abstract base class' if $test->is_abstract;

    my $class = $test->class;
    critic_module_ok($class);
    return;
}

sub constructor : Test(3) {
    my $test = shift;
    return 'abstract base class' if $test->is_abstract;

    my $class = $test->class;
    can_ok $class, 'new';
    ok my  $cs = $class->new, '... and the constructor should succeed';
    isa_ok $cs,  $class,      '... and the object it returns';
    return;
}

sub test_attributes : Tests {
    my $test = shift;
    return 'abstract base class' if $test->is_abstract;

    my $attributes = $test->attributes;
    return 'no attributes' unless $attributes;

    $test->num_tests((scalar keys %$attributes)*3);

    foreach my $a ( keys %$attributes ) {
        $test->_attribute($a, $attributes->{$a});
    }
    return;
}

sub _attribute {
    my ($test, $attribute, $expected) = @_;

    $test->setup;
    my $obj = $test->our_object;

    can_ok $obj, $attribute;
    ok ! defined $obj->$attribute, "...and '$attribute' should start out undefined";
    $test->set_attributes;
    is $obj->$attribute, $expected,'...and setting its value should succeed';

    return;
}

sub set_attributes {
    my $test = shift;
    my $obj = $test->our_object;
    my $attributes = $test->attributes;
    foreach my $a ( keys %$attributes ) {
        $obj->$a($attributes->{$a});
    }
    return;
}

sub attributes {
    my $test = shift;

    my $attributes = $test->{attributes};
    return $attributes if $attributes;

    $attributes = { %{$test->build_attributes} }; # make a copy we can manipulate
    foreach my $a ( keys %$attributes ) {
        my $val_or_sub = $attributes->{$a};
        my $ref = ref $val_or_sub;
        if ($ref and $ref eq 'CODE') {
            $val_or_sub = &$val_or_sub($test);
            $attributes->{$a} = $val_or_sub;
        }
    }

    return $test->{attributes} = $attributes;
}

sub build_attributes { die 'build_attributes() must be provided by child class.' }

1;

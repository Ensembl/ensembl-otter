package CriticModule;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(critic_module_ok);

use File::Spec;

use Test::Perl::Critic;

sub import {
    my ($self, %args) = @_;
    Test::Perl::Critic->import(%args);
    $self->export_to_level( 1, $self, qw(critic_module_ok) );
    1;
}

sub critic_module_ok {
    my ($module, $test_name, @args) = @_;

    my @mod_dir = split(/::/, $module);
    my $mod_file = pop(@mod_dir) . ".pm";
    my $mod_rel_path = File::Spec->catfile(@mod_dir, $mod_file);
    my $mod_path = $INC{$mod_rel_path};

    unless ($mod_path) {
        my $ok = fail($test_name || "CriticModule for \"$module\"");
        diag("Cannot find '$module' in %INC - did you forget to 'use_ok($module)' first?");
        return $ok;
    }

    return critic_ok($mod_path, $test_name, @args);
}

1;

use strict;
use warnings;

use File::Spec;
use Test::Perl::Critic (-severity => 3);

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


package Bio::Otter::Debug;

use strict;
use warnings;

my $DEBUG = { };

sub debug {
    my ($pkg, $key, @args) = @_;
    _verify_keys($key);
    my $debug = $pkg->_debug($key, @args);
    return $debug;
}

sub _debug {
    my ($pkg, $key, @args) = @_;
    if (@args) {
        my ($value) = @args;
        $value = $value ? 1 : 0;
        $DEBUG->{$key} = $value;
        warn sprintf "DEBUG: %s = %d\n", $key, $value;
    }
    my $debug = $DEBUG->{$key} ? 1 : 0;
    return $debug;
}

sub set {
    my ($pkg, $keys) = @_;
    my @keys = $keys =~ /[^,;[:space:]]+/g;
    _verify_keys(@keys);
    $pkg->_debug($_, 1) for @keys;
    return;
}

my $key_hash = { };

sub add_keys {
    my ($pkg, @keys) = @_;
    $key_hash->{uc $_}++ for @keys;
    return;
}

# deliberately exploiting variable aliasing here
sub _verify_keys { ## no critic (Subroutines::RequireArgUnpacking)
    my @bad_keys = grep { ! $key_hash->{uc $_} } @_;
    die sprintf
        "Bad debug keys: %s\nCorrect your spelling or add this line to your code:\n    %s->add_keys(%s)\n"
        , (join ', ', @bad_keys), __PACKAGE__, (join ', ', map { "'$_'" } @bad_keys)
        if @bad_keys;
    $_ = uc $_ for @_;
    return;
}

1;

__END__

=head1 DESCRIPTION

A flexible debugging configuration API.

=head1 USAGE

The API is OO and consists entirely of class methods.

You can get/set the value associated to a key or set the value to 1
for each key in a list of keys.

Keys are case insensitive.  Key lists are strings split at commas,
semicolons and whitespace.  Values are coerced to 0 or 1.

Using an invalid key die()s.  You must register valid keys before
using them.

=over 4

=item * C<$pkg-E<gt>debug($key)>

Get the debug level for C<$key>.

=item * C<$pkg-E<gt>debug($key, $value)>

Set the debug level for C<$key> to C<1> if C<$value> is true or C<0>
if $value is false.  This printd a warning to standard error reporting
the key and its value.

=item * C<$pkg-E<gt>set($key_list)>

Split C<$key_list> at commas, semicolons and whitespace and set the
debug level for each key to C<1>.

=item * C<$pkg-E<gt>add_keys(@keys)>

Register each key in C<@keys> as valid so that it can be used.  Using
an invalid key die()s.

=back

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


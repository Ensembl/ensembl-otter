
### Bio::Otter::Utils::Config::Ini

package Bio::Otter::Utils::Config::Ini;

use strict;
use warnings;
use Hum::Sort qw( ace_sort );

use base qw( Exporter );

our @EXPORT_OK = qw(
    config_ini_format
);

sub config_ini_format {
    my ($config, $key) = @_;
    my @keys = sort { ace_sort($a, $b) } keys %{$config};
    # move the special key to the front if possible
    @keys = ( $key, grep { $_ ne $key } @keys )
        if defined $key && defined $config->{$key};
    return sprintf "\n%s\n", join "\n", map { _format_stanza($_, $config->{$_}) } @keys;
}

sub _format_stanza {
    my ($name, $stanza) = @_;
    return sprintf "[%s]\n%s"
        , $name, join '', map { _format_key_value($_, $stanza->{$_}) } sort { ace_sort($a, $b) } keys %{$stanza};
}

sub _format_key_value {
    my ($key, $value) = @_;
    $value = join ' ; ', @{$value} if ref $value;
    return sprintf "%s = %s\n", $key, $value;
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::Config::Ini

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


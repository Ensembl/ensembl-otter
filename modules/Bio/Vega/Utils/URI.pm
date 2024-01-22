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


### Bio::Vega::Utils::URI

package Bio::Vega::Utils::URI;

use strict;
use warnings;
use URI::Escape qw{ uri_escape };

use base 'Exporter';

our @EXPORT_OK = qw{ open_uri uri_config_how };

sub open_uri {
    my ($path, $param_hash) = @_;

    my $form = '';
    if ($param_hash) {
        $form = '?' . join('&', map { "$_=" . uri_escape($param_hash->{$_}) } keys %$param_hash);
    }
    return system(open_uri_command(), $path . $form) == 0;
}

sub open_uri_command {
    return $^O eq 'darwin' ? 'open' : 'xdg-open';
}


sub uri_config_how {
    my ($self) = @_;
    if (-x '/usr/bin/gnome-default-applications-properties') {
        return
          (" You appear to be using the Gnome environment.\n".
           " Please update your System > Preferences > Preferred Applications.\n");
    } else {
        return
          (" Please consult your operating system's manual or\n".
           " systems administrator to find out how to make\n".
           " the '".open_uri_command()."' command work.\n");
    }
}


1;

__END__

=head1 NAME - Bio::Vega::Utils::URI

=head1 EXAMPLE

    my $success = open_uri('mailto:jgrg@sanger.ac.uk',
        {
            subject => "A test & other & stuff",
            body    => "Some very interesting text & stuff\nin here over several\nlines.",
        });

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


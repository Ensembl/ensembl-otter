
### Bio::Otter::Lace::Defaults

package Bio::Otter::Lace::Defaults;

use strict;
use Carp;
use Getopt::Long 'GetOptions';
use Symbol 'gensym';
use Bio::Otter::Lace::Client;

my $defaults = {};
my @option_fields = qw{ host port author email write_access };

sub save_option {
    my( $option, $value ) = @_;

    $defaults->{$option} = $value;
}

sub do_getopt {
    my( @script_args ) = @_;

    GetOptions(
        'host=s'        => \&save_option,
        'port=s'        => \&save_option,
        'author=s'      => \&save_option,
        'email=s'       => \&save_option,
        'write_access!' => \&save_option,
        @script_args,
    ) or confess "Error processing command line";
    
    my ($this_user, $home_dir) = (getpwuid($<))[0,7];
    
    # We get options from:
    #   command line
    #   ~/.otter_config
    #   $ENV{'OTTER_HOME'}/otter_config
    #   /etc/otter_config
    #   hardwired defaults (in this subroutine)
    my @conf_files = ("$home_dir/.otter_config");
    if ($ENV{'OTTER_HOME'}) {
        # Only add if OTTER_HOME environment variable is set
        push(@conf_files, "$ENV{'OTTER_HOME'}/otter_config");
    }
    push(@conf_files, '/etc/otter_config');
    
    # If we are missing any values in the $defaults hash, try
    # and fill them in from each file in turn.
    until (all_options_are_filled()) {
        my $file = shift @conf_files or last;
        warn "Getting options from '$file'";
        if (my $file_opts = options_from_file($file)) {
            foreach my $field (@option_fields) {
                if (! $defaults->{$field} and $file_opts->{$field}) {
                    $defaults->{$field} = $file_opts->{$field};
                }
            }
        }
    }
    
    # Fallback on hardwired defaults
    $defaults->{'host'}         ||= 'localhost';
    $defaults->{'port'}         ||= 39312;
    $defaults->{'author'}       ||= $this_user;
    $defaults->{'email'}        ||= $this_user;
    $defaults->{'write_access'} ||= 0;
}

sub make_Client {
    my $client = Bio::Otter::Lace::Client->new;
    while (my ($meth, $value) = each %$defaults) {
        $client->$meth($value);
    }
    return $client;
}

sub options_from_file {
    my( $file ) = @_;
    
    my $fh = gensym();
    
    # Just return if file does not exist or is unreadable
    open $fh, $file or return;
    
    my $in_client = 0;
    my $opts = {};
    while (<$fh>) {
        chomp;
        
        # Only look at client stanza
        if (/^\[client\]/) {
            $in_client = 1;
        }
        elsif (/^$/) {
            $in_client = 0;
        }
        else {
            next unless $in_client;
        }
        
        if (/([^=]+)\s*=\s*([^=]+)/) {
            #warn "Got '$1' = '$2'";
            $opts->{$1} = $2;
        }
    }
    
    close $fh;
    
    return $opts;
}

sub all_options_are_filled {
    foreach my $field (@option_fields) {
        unless ($defaults->{$field}) {
            warn "Missing '$field'";
            return 0;
        }
    }
    return 1;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Defaults

=head1 DESCRIPTION

Loads default values needed for creation of an
otter client from:

  command line
  ~/.otter_config
  $ENV{'OTTER_HOME'}/otter_config
  /etc/otter_config
  hardwired defaults (in this module)

The values filled in, which can be given by
command line options of the same name, are:

=over4

=item B<host>

Defaults to B<localhost>

=item B<port>

Defaults to B<39312>

=item B<author>

Defaults to user name

=item B<email>

Defaults to user name

=item B<write_access>

Defaults to B<0>

=back

=head1 SYNOPSIS

  use Bio::Otter::Lace::Defaults;

  # Script can add Getopt::Long compatible options
  my $foo = 'bar';
  Bio::Otter::Lace::Defaults::do_getopt(
      'foo=s'   => \$foo,     
      );

  # Make a Bio::Otter::Lace::Client
  my $client = Bio::Otter::Lace::Defaults::make_Client();

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


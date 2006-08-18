
### Bio::Otter::Lace::Defaults

package Bio::Otter::Lace::Defaults;

use strict;
use Carp;
use Getopt::Long 'GetOptions';
use Symbol 'gensym';
use Config::IniFiles;
use Data::Dumper;
use Bio::Otter::Lace::Client;

my $CLIENT_STANZA   = 'client';
my $DEFAULT_TAG     = 'default';
my $DEBUG_CONFIG    = 0;
#-------------------------------
my $CONFIG_INIFILES = [];
my %OPTIONS_TO_TIE  = (
                       -default => $DEFAULT_TAG, 
                       -nocase  => 1,
                       );

my $HARDWIRED = {};
tie %$HARDWIRED, 'Config::IniFiles', (-file => \*DATA, %OPTIONS_TO_TIE);
# Make these accessible without call to do_getopt()
push(@$CONFIG_INIFILES, $HARDWIRED); 

# The tied hash for the GetOptions variables
my $DEFAULTS = {};
tie %$DEFAULTS, 'Config::IniFiles', %OPTIONS_TO_TIE;

our $GETOPT_ERRSTR  = undef;
my @CLIENT_OPTIONS = qw(
    host=s
    port=s
    author=s
    email=s
    pipeline!
    write_access!
    group=s
    gene_type_prefix=s
    debug!
    misc_acefile=s
    logdir=s
    );

# @CLIENT_OPTIONS is Getopt::GetOptions() keys which will be included in the 
# $DEFAULTS->{$CLIENT_STANZA} hash.  To add another client option just include in above
# and if necessary add to hardwired defaults in do_getopt().

    # not a method
sub save_option {
    my ($option, $value) = @_;
    $DEFAULTS->{$CLIENT_STANZA}->{$option} = $value;
}

    # not a method
sub save_deep_option {
    my $getopt = $_[1];
    my ($option, $value) = split(/=/, $getopt, 2);
    $option = [ split(/\./, $option) ];
    my $param = pop @$option;
    return unless @$option;
    my $opt_str = join('.', @$option);
    $DEFAULTS->{$opt_str} ||= {};
    $DEFAULTS->{$opt_str}->{$param} = $value;
}


my ($THIS_USER, $HOME_DIR) = (getpwuid($<))[0,7];    
my $CALLED = "$0 @ARGV";


################################################
#
## PUBLIC METHODS
#
################################################


=head1 do_getopt

 A wrapper function around GetOptions

    We get options from:
     - files provided by list_config_files()
     - command line
     - hardwired defaults (in this subroutine)
    overriding as we go.

 Returns true on success, false otherwise, in the latter case 
the Bio::Otter::Lace::Defaults::GETOPT_ERRSTR variable is populated.

Suggested usage:
 @options = (-dataset => \$dataset);
 Bio::Otter::Lace::Defaults::do_getopt(@options) || die $Bio::Otter::Lace::Defaults::GETOPT_ERRSTR;

=cut

sub do_getopt {
    my (@script_args) = @_;

    ## If you have any 'local defaults' that you want to take precedence
    #  over the configuration files' settings, unshift them into @ARGV
    #  before running do_getopt()

    $CONFIG_INIFILES = [];    # clear and add in case of multiple calls
    push(@$CONFIG_INIFILES, $HARDWIRED);

    my @conf_files = list_config_files();
    my $file_options = [];
    foreach my $file (@conf_files) {
        if (my $file_opts = options_from_file($file)) {
            push(@$CONFIG_INIFILES, $file_opts);
        }
    }
    ############################################################################
    ############################################################################
    my $start = "Called as:\n\t$CALLED\nGetOptions() Error parsing options:";
    $GETOPT_ERRSTR = undef;    # in case this gets called more than once
    GetOptions(
        'h|help!' => \&show_help,

        # map {} makes these lines dynamically from @CLIENT_OPTIONS
        # 'host=s'        => \&save_option,
        (map { $_ => \&save_option } @CLIENT_OPTIONS),

        # this allows setting of options as in the config file
        'cfgstr=s' => \&save_deep_option,

        # this is just a synonym feel free to add more
        'view' => sub { $DEFAULTS->{$CLIENT_STANZA}->{'write_access'} = 0 },
        'local_fasta=s' => sub { $DEFAULTS->{'local_blast'}->{'database'} = $_[1] },
        'noblast' => sub {
            map { $_->{'local_blast'} = {} if exists $_->{'local_blast'} }
              @$CONFIG_INIFILES;
        },

        # this allows multiple extra config file to be used
        'cfgfile=s' => sub {
            my $opts = options_from_file($_[1]);
            push(@$CONFIG_INIFILES, $opts) if $opts;
        },
        'log-file=s' => sub { die "log-file option is obsolete - use logdir" },

        # 'prebinpath=s' => sub { $ENV{PATH} = "$_[1]:$ENV{PATH}"; },

        # these are the caller script's options
        @script_args,
      )
      or show_help();
    ############################################################################
    ############################################################################

    push(@$CONFIG_INIFILES, $DEFAULTS);

    # now safe to call any subs which are required to setup stuff

    return 1;
}

sub show_help {
    exec('perldoc', $0);
}

sub make_Client {
    return Bio::Otter::Lace::Client->new;
}

sub option_from_array{
    my ($array) = @_;
    $array    ||= [];
    my $value   = undef;
    warn "\noption from array called // @$array //\n" if $DEBUG_CONFIG;

    my @arr_copy = @{$array};
    my $first    = shift @arr_copy;

    my $allow_hash = 1; # allow hash for first call to set_value

    my $set_value = sub {
        my ($conf_val, $found) = @_;
        my $value_is_hash    = ref($value)    eq 'HASH';
        my $conf_val_is_hash = ref($conf_val) eq 'HASH';
        warn sprintf("got // value '%s', found '%s' //\n",$conf_val||'undef', $found) if $DEBUG_CONFIG;
        return unless $found;
        if(($value_is_hash || $allow_hash) && $conf_val_is_hash){
            # initialise as first time it will be undef
            $value ||= {};
            # overwrite the previous $value
            $value   = { %$value, %$conf_val };
        }else{
            $value = $conf_val;
        }
        $allow_hash = 0;
    };

    # get first file
    #    - get default option from that
    #    - get option from that (if exists) and overwrite
    # get next file
    #    - get default option from that and overwrite
    #    - get option from that (if exists) and overwrite

    foreach my $conf (@$CONFIG_INIFILES) {
        $set_value->(
            __internal_option_from_array($conf, [ $DEFAULT_TAG, @arr_copy ]));
        $set_value->(
            __internal_option_from_array($conf, [ $first,       @arr_copy ]));
    }

    printf(STDERR "Returning value '%s' for [@$array]\n\n", $value || 'undef')
        if $DEBUG_CONFIG;

    return $value;
}

sub list_config_files{
    #   ~/.otter_config
    #   $ENV{'OTTER_HOME'}/otter_config
    #   /etc/otter_config
    my @conf_files = ();
    push(@conf_files, "/etc/otter_config") if -e "/etc/otter_config";

    if ($ENV{'OTTER_HOME'}) {
        # Only add if OTTER_HOME environment variable is set
        push(@conf_files, "$ENV{'OTTER_HOME'}/otter_config");
    }
    push(@conf_files, "$HOME_DIR/.otter_config");
    return @conf_files;
}

sub save_all_config_files{
    eval{
        foreach my $config(@$CONFIG_INIFILES){
            my $obj = tied(%$config);
            next unless $obj;
            my $filename = $obj->GetFileName();
            warn "Saving '$filename' \n";
            next unless -w $filename;
            warn "       '$filename' is writeable\n";
            $obj->WriteConfig($filename) or die "Error Writing '$filename'";
            warn "Wrote '$filename'\n";
        }
    };
    if($@){
        warn "Failed Saving Config:\n$@";
    }
}


################################################
#
## UTILITY METHODS - MADE FOR YOU
#
################################################

sub fetch_gene_type_prefix {
    return option_from_array([ $CLIENT_STANZA, 'gene_type_prefix' ]);
}

sub fetch_pipeline_switch {
    return option_from_array([ $CLIENT_STANZA, 'pipeline' ]) ? 1 : 0;
}

sub pipehead {
    return option_from_array([ $CLIENT_STANZA, 'pipehead' ]) ? 1 : 0;
}

sub misc_acefile {
    return option_from_array([ $CLIENT_STANZA, 'misc_acefile' ]);
}

sub methods_acefile {
    return option_from_array([ $CLIENT_STANZA, 'methods_acefile' ]);
}

sub pipe_name {

    return (!fetch_pipeline_switch())
                ? 'no pipeline'
                : pipehead()
                    ? 'new pipeline'
                    : 'old pipeline';
}


sub get_config_list{
    return $CONFIG_INIFILES;
}

sub get_dot_otter_config{
    my $configs = get_config_list();
    my $dot_otter_config;
    my $location   = "$HOME_DIR/.otter_config";
    foreach my $c(@{$configs}){
        my $obj = tied(%$c);
        next unless $obj;
        my $obj_file = $obj->GetFileName;
        $dot_otter_config = $c if $obj_file && $obj_file eq $location;
        last if $dot_otter_config;
    }
    unless($dot_otter_config){
        open(my $fh, ">>$location") || die "ERROR $!";
        print $fh "[client]\n";
        close $fh;
        $dot_otter_config = options_from_file($location);
    }
    return $dot_otter_config;
}

sub cmd_line{
    return $CALLED;
}


################################################
#
## INTERNAL METHODS - NOT MADE FOR YOU
#
################################################
# options_from_file

sub options_from_file{
    my ($file, $previous) = @_;
    return unless -e $file;
    my $ini;
    print STDERR "Trying $file\n" if $DEBUG_CONFIG;
    tie %$ini, 'Config::IniFiles', ( -file => $file, %OPTIONS_TO_TIE)
      or confess "Error opening '$file':\n", join("\n", @Config::IniFiles::errors);
    return $ini;
}

sub __internal_option_from_array {
    my ($inifiles, $array) = @_;

    return unless tied(%$inifiles);
    
    if ($DEBUG_CONFIG) {
        my $filename = tied(%$inifiles)->GetFileName() || 'no filename';

        warn
    "option from array inifile called // $inifiles @$array // looking at '$filename'\n";
    }

    my $param = pop @$array;
    my $section = join(".", @$array);
    warn sprintf "param '%s' and section '%s'\n", $param, $section
      if $DEBUG_CONFIG;
    my $value = undef;
    my $found = 0;

    my $stem_finder = sub {
        my ($s, $p) = @_;
        my $val  = {};
        my $stem = "$s.$p";
        foreach my $k (keys(%$inifiles)) {
            $val = { %$val, ($1 => $inifiles->{$k}) } if $k =~ /^$stem\.(.+)/;
        }
        return (scalar(keys(%$val)) ? $val : undef);
    };

    # get the explicit call for a parameter client host
    if (exists $inifiles->{$section} && exists $inifiles->{$section}->{$param})
    {

        #print STDERR "1\n";
        $value = $inifiles->{$section}->{$param};
        $found = 1;

        # get the hash for a block [default.use_filters]
    }
    elsif (exists $inifiles->{ $section . ".$param" }) {

        #print STDERR "2\n";
        $value = $inifiles->{ $section . ".$param" };
        $found = 1;

# get the hash for a block [default]. this is same as the above but for only single named stanzas!
    }
    elsif ((!$section) && exists $inifiles->{"$param"}) {

        #print STDERR "3\n";
        $value = $inifiles->{"$param"};
        $found = 1;

        # get the hash for a group of blocks [default.filter]
        # will include [default.filter.repeatmask], [default.filter.cpg] ...
        # this can be a pain, not sure stem finder is working as expected
    }
    elsif (my $stem = $stem_finder->($section, $param)) {

        #print STDERR "4\n";
        $value = $stem;
        $found = 1;

        # all the above failed to find the specified node of tree
    }
    else {

        #print STDERR "5\n";
        $found = 0;
    }
    return ($value, $found);
}

1;

=head1 NAME - Bio::Otter::Lace::Defaults

=head1 DESCRIPTION

Loads default values needed for creation of an
otter client from:

  command line
  ~/.otter_config
  $ENV{'OTTER_HOME'}/otter_config
  /etc/otter_config
  hardwired defaults (in this module)

in that order.  The values filled in, which can
be given by command line options of the same
name, are:

=over 4

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


=head1 EXAMPLE

Here's an example config file:


  [client]
  port=33999

  [default.use_filters]
  trf=1
  est2genome_mouse=1

  [zebrafish.use_filters]
  est2genome_mouse=0

  [default.filter.est2genome_mouse]
  module=Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity
  max_coverage=12


You can also specify options on the command line 
using the B<cfgstr> option.  Thus:

    -cfgstr zebrafish.use_filters.est2genome_mouse=0

will switch off est2genome_mouse for the
zebrafish dataset exactly as the config file example
above does.

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

=cut


__DATA__
##########
## This is where the HARDWIRED ABSOLUTE DEFAULTS are stored
[client]
host=localhost
port=33999
write_access=0
debug=1
pipeline=1 
pipehead=0


### Bio::Otter::Lace::Defaults

package Bio::Otter::Lace::Defaults;

use strict;
use Carp;
use Getopt::Long 'GetOptions';
use Symbol 'gensym';
use Bio::Otter::Lace::Client;

our $CLIENT_STANZA  = 'client';
our $DEFAULT_TAG    = 'default';
our $DEFAULTS       = {};
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
    );

# @CLIENT_OPTIONS is Getopt::GetOptions() keys which will be included in the 
# $DEFAULTS->{$CLIENT_STANZA} hash.  To add another client option just include in above
# and if necessary add to hardwired defaults in do_getopt().

our $save_option = sub {
    my( $option, $value ) = @_;
    $DEFAULTS->{$CLIENT_STANZA}->{$option} = $value;
};
our $save_deep_option = sub {
    my $getopt = $_[1];
    my ($option, $value) = split(/=/, $getopt,2);
    $option = [split(/\./, $option)];
    set_hash_val($DEFAULTS, $option, $value);
};

sub fetch_gene_type_prefix {
    return $DEFAULTS->{$CLIENT_STANZA}->{'gene_type_prefix'};
}

sub fetch_pipeline_switch {
    return $DEFAULTS->{$CLIENT_STANZA}->{'pipeline'} ? 1 : 0;
}

sub do_getopt {
    my( @script_args ) = @_;

    my ($this_user, $home_dir) = (getpwuid($<))[0,7];    
    
    # We get options from:
    #   files provided by list_config_files()
    #   command line
    #   hardwired defaults (in this subroutine)
    # overriding as we go.
    my @conf_files = list_config_files();
    # warn "@conf_files \n";
    # If we are missing any values in the $DEFAULTS hash, try
    # and fill them in from each file in turn.
    my $file_options = [];
    foreach my $file(@conf_files){
	# warn "Getting options from '$file'\n";
	if (my $file_opts = options_from_file($file)) {
	    push(@$file_options, $file_opts);
	}
    }

    $DEFAULTS = merge_options_for_stanzas($file_options);

    GetOptions(
	       # map {} makes these lines dynamically from @CLIENT_OPTIONS
	       # 'host=s'        => $save_option,
	       ( map { $_ => $save_option } @CLIENT_OPTIONS ),
	       # this allows setting of options as in the config file
	       'cfgstr=s'       => $save_deep_option,
	       # this is just a synonym feel free to add more
	       'view'          => sub{ $DEFAULTS->{$CLIENT_STANZA}->{'write_access'} = 0 },
	       # these are the caller script's options
	       @script_args,
	       ) or return 0;

    merge_all_optionals();
    check_spelling(); # only does client ATM

    # Fallback on hardwired defaults
    $DEFAULTS->{$CLIENT_STANZA}->{'host'}         ||= 'localhost';
    $DEFAULTS->{$CLIENT_STANZA}->{'port'}         ||= 39312;
    $DEFAULTS->{$CLIENT_STANZA}->{'author'}       ||= $this_user;
    $DEFAULTS->{$CLIENT_STANZA}->{'email'}        ||= $this_user;
    $DEFAULTS->{$CLIENT_STANZA}->{'write_access'} ||= 0;
    $DEFAULTS->{$CLIENT_STANZA}->{'debug'}          = 1
        unless defined($DEFAULTS->{$CLIENT_STANZA}->{'debug'});
    $DEFAULTS->{$CLIENT_STANZA}->{'pipeline'}       = 1 
	unless defined($DEFAULTS->{$CLIENT_STANZA}->{'pipeline'});

    return 1;
}

# merge_options_for_stanza 
# this goes through the hashes over writing earlier
# option/values with later ones. 
# so $array->[0]->{option} is overwritten by $array->[1]->{option}
# and so on...
# wants array ref of hash refs

sub merge_options_for_stanzas{
    my ( $array ) = @_;
    my $return_hash = {};
    foreach my $hash(@$array){
	$return_hash = merge($return_hash, $hash);
    }
    return $return_hash;
}

sub make_Client {
    my $client = Bio::Otter::Lace::Client->new;

    $client->all_options($DEFAULTS);

    return $client;
}

# options_from_file
# reads the whole file into a hash
# $hash->{stanza}->{option}->{value}

sub options_from_file {
    my( $file ) = @_;
    
    my $fh = gensym();
    
    # Just return if file does not exist or is unreadable
    open $fh, $file or return;
    
    my $current_stanza = '';
    my $all_opts = {};

    while (<$fh>) {
        chomp;
        next if /^\#/ || /^$/; # ignore comments and blank
        s/\s$//;
        # Only look at client stanza
        if (/^\[([\w\._]+)\]/) {
            $current_stanza = $1;
	    set_hash_val($all_opts, [ split(/\./, $current_stanza)], {});
        }

        if (/([^=]+)\s*=\s*([^\n]+)/) {
            # warn "Got '$1' = '$2' \n";
	    set_hash_val($all_opts, [ split(/\./, $current_stanza), lc $1 ], $2);
        }
    }
    
    close $fh;

    return $all_opts;
}

sub merge_all_optionals{
    my @overrides = keys(%{$DEFAULTS->{$DEFAULT_TAG}});
    my @toplevels = grep { !(/$DEFAULT_TAG/ || /$CLIENT_STANZA/) }  keys(%$DEFAULTS);

    foreach my $i(@toplevels){

	# this check is pretty crude and ONLY handles two levels
	my $check = { map{ $_, 1} keys(%{$DEFAULTS->{$i}}) };
	foreach my $j(@overrides){
	    delete $check->{$j};
	    # warn " ***** merging \$DEFAULTS->{'$DEFAULT_TAG'}->{'$j'} with \$DEFAULTS->{'$i'}->{'$j'}\n";
	    $DEFAULTS->{$i}->{$j} = merge($DEFAULTS->{$DEFAULT_TAG}->{$j},
					  $DEFAULTS->{$i}->{$j});
	}
	my @poss_errs = map{"<$_>"} keys(%$check);
	warn "Are you sure <$i> has sublevel(s): " . join(" ", @poss_errs) . 
	    " *** PLEASE CHECK CONFIG FILES ***\n" if @poss_errs;
    }
}

# this checks spelling for all @CLIENT_OPTIONS
# an easy mistake to make in config files which 
# would otherwise be ignored. E.G.
# [client]
# pipleine=0
sub check_spelling{
    my $actuals = { map {$_, 1} keys(%{$DEFAULTS->{$CLIENT_STANZA}})};
    map { m/^(\w+)/; delete $actuals->{$1} } @CLIENT_OPTIONS;
    my @poss_errs =  map{"<$_>"} keys(%$actuals);
    warn "Possible typo for option(s): " . join(" ", @poss_errs ) . 
	" *** PLEASE CHECK CONFIG FILES ***\n" if @poss_errs;
}

sub list_config_files{
    #   ~/.otter_config
    #   $ENV{'OTTER_HOME'}/otter_config
    #   /etc/otter_config
    my @conf_files = ("/etc/otter_config");

    if ($ENV{'OTTER_HOME'}) {
        # Only add if OTTER_HOME environment variable is set
        push(@conf_files, "$ENV{'OTTER_HOME'}/otter_config");
    }
    my ($home_dir) = (getpwuid($<))[7];
    push(@conf_files, "$home_dir/.otter_config");
    return @conf_files;
}

################################################
sub set_hash_val{
    my ($hash, $keys, $value) = @_;
    my $lastKey = lc(pop @$keys);
    
    foreach my $key (@$keys) {
	$key = lc $key;
	if (not exists($hash->{$key})) {
	    $hash->{$key} = {};
	} elsif (ref($hash->{$key}) ne 'HASH') {
	    my $oldVal = $hash->{$key};
	    $hash->{$key} = {};
	    warn "Looks like something's been defined twice\n";
	    $hash->{$key}{'_setHashVal_'} = $oldVal;
	}
	# Traverse hash
	$hash = $hash->{$key};
    }
    if(not exists($hash->{$lastKey})){
        $hash->{$lastKey} = $value;
    }else{
        warn "Having to use '_setHashVal_' as key and value in hash THIS IS BAD!\n";
        $hash->{'_setHashVal_'} = $value;
    }
}

################################################
# slightly modified from the guts of Hash::Merge
# works on a right precedence behaviour
# as would $hash = { %$first, %$second } in perl.
#
sub merge {
    my ( $left, $right ) = @_;
    return _merge_hashes( $left, $right ) if UNIVERSAL::isa( $right, 'HASH' );
    return defined $right ? $right : $left;
}	
sub _merge_hashes {
    my ( $left, $right ) = @_;
    die "Arguments for _merge_hashes must be hash references" unless 
	UNIVERSAL::isa( $left, 'HASH' ) && UNIVERSAL::isa( $right, 'HASH' );

    my $newhash;
    foreach my $leftkey( keys %$left ) {
	if ( exists $right->{ $leftkey } ) {
	    $newhash->{ $leftkey } = merge ( $left->{ $leftkey }, $right->{ $leftkey } );
	}else{
	    $newhash->{ $leftkey } = $left->{ $leftkey };
	}
    }
    foreach my $rightkey( keys %$right ){ 
	if( !exists $left->{ $rightkey } ){
	    $newhash->{ $rightkey } = $right->{ $rightkey };
	}
    }
    return $newhash;
}



## sets the known gene methods for a particular XaceSeqChooser
sub set_known_GeneMethods{
    my ($self , $xace ) = @_ ;
    my @methods_mutable =  $self->get_default_GeneMethods ;
    
    confess "uneven number of arguments" if @methods_mutable % 2;
         
    for (my $i = 0; $i < @methods_mutable; $i+= 2) {
        my ($name, $flags) = @methods_mutable[$i, $i+1];
        my ($is_mutable, $is_coding , $has_parent) = @$flags;
        my $meth = $xace->fetch_GeneMethod($name);
        $meth->is_mutable($is_mutable);
        $meth->is_coding($is_coding); 
        $meth->has_parent($has_parent);
        $xace->add_GeneMethod($meth);
    }
}

## this method stores the defualt GeneMethod values. 
sub get_default_GeneMethods{
    my ($self ) = @_ ;       
    my @methods = (

        # note: if the sub category field is 0 it is a parent if it is 1 it is a child of the last parent listed 
        # Method name               Editable?  Coding?  sub-category of?        
        # New set of methods for Otter
        Coding                   => [1,         1,          0],
        Transcript               => [1,         0,          0],
        Non_coding               => [1,         0,          1],
        Ambiguous_ORF            => [1,         0,          1],
        Immature                 => [1,         0,          1],
        Antisense                => [1,         0,          1],
        IG_segment               => [1,         1,          0],
        Putative                 => [1,         0,          0],
        Pseudogene               => [1,         0,          0],
        Processed_pseudogene     => [1,         0,          1],
        Unprocessed_pseudogene   => [1,         0,          1],
        Predicted                => [1,         0,          0],
        Transposon               => [1,         1,          0],
        # newly added - truncated versions of above methods        
        Coding_trunc                    => [0,         1,          1],
        Transcript_trunc                => [0,         0,          0],
        Non_coding_trunc                => [0,         0,          1],
        Ambiguous_ORF_trunc             => [0,         0,          1],
        Immature_trunc                  => [0,         0,          1],
        Antisense_trunc                 => [0,         0,          1],
        IG_segment_trunc                => [0,         1,          0],
        Putative_trunc                  => [0,         0,          0],
        Pseudogene_trunc                => [0,         0,          0],
        Processed_pseudogene_trunc      => [0,         0,          1],
        Unprocessed_pseudogene_trunc    => [0,         0,          1],
        Predicted_trunc                 => [0,         0,          0],  
        
        # Auto-analysis gene types (non-editable)
        fgenesh                  => [0,         1],
        FGENES                   => [0,         1],
        GENSCAN                  => [0,         1],
        HALFWISE                 => [0,         0],
        SPAN                     => [0,         0],
        EnsEMBL                  => [0,         1],
        genomewise               => [0,         1],
        'WashU-Supported'        => [0,         1],
        'WashU-Putative'         => [0,         0],
        'WashU-Pseudogene'       => [0,         0],
    );
    return @methods;

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

  [default.use_FilteRs]
  trf=1
  est2genome_mouse=1

  [zebrafish.use_filters]
  est2genome_mouse=0

  [default.filter.est2genome_mouse]
  module=Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity
  max_coverage=12


which will make this hash:

    $Bio::Otter::Lace::DEFAULTS = {
        'client' => {
            'port' => 33999,
            },       
        'default' => {
            'use_filters' => {
                'trf' => 1,
                'est2genome_mouse' => 1
                },
            'filter' => {
                'est2genome_mouse' => {
                    'module' => 'Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity',
                    'max_coverage' => 12
                },
            },
        },
        'zebrafish' => {
            'use_filters' => {
                'trf' => 1,
                'est2genome_mouse' => 0,
            },
        },
    };

N.B. ALL hash keys are lower cased to ensure ease
of look up.  You can also specify options on the
command line using the B<cfgstr> option.  Thus:

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


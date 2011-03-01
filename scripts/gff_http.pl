#!/usr/bin/perl

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use URI::Escape qw(uri_escape uri_unescape);

my $LOG     = 1;

my %args;
foreach my $pair (@ARGV) {
    my ($key, $val) = split(/=/, $pair);
    $args{uri_unescape($key)} = uri_unescape($val);
}

# pull off arguments meant for us

my $url_root        = delete $args{'url_root'};
my $server_script   = delete $args{'server_script'};
my $session_dir     = delete $args{'session_dir'};
my $cookie_jar      = delete $args{'cookie_jar'};
my $process_gff     = delete $args{'process_gff_file'};

chdir($session_dir) or die "Could not chdir to '$session_dir'; $!";

open my $log_file, '>>', 'gff_log.txt';

$args{log} = 1 if $LOG; # enable logging on the server
$args{rebase} = 1 unless $ENV{OTTERLACE_CHROMOSOME_COORDINATES};

# concatenate the rest of the arguments into a parameter string

my $params = join '&', map { uri_escape($_).'='.uri_escape($args{$_}) } keys %args;

my $gff_filename = sprintf '%s_%s.gff', $args{gff_source}, md5_hex($params);

my $top_dir = 'gff_cache';

unless (-d $top_dir) {
    mkdir $top_dir or die "Failed to create toplevel cache directory: $!\n";
}

my $cache_file = $top_dir.'/'.$gff_filename;

if (-e $cache_file) {
    # cache hit
    print $log_file "$gff_filename: cache hit\n";
    open my $gff_file, '<', $cache_file or die "Failed to open cache file: $!\n";
    while (<$gff_file>) { print; }
    close $gff_file or die "Failed to close cache file: $!\n";
    close STDOUT or die "Error writing to STDOUT; $!";
}
else {
    # cache miss
    
    # only require these packages now, so we don't take the import hit on a cache hit
    
    require LWP::UserAgent;
    require HTTP::Request;
    require HTTP::Cookies::Netscape;
    require DBI;
    
    print $log_file "$gff_filename: cache miss\n";
    
    my $request = HTTP::Request->new;

    $request->method('GET');

    #$request->accept_decodable(HTTP::Message::Decodable);

    my $url = $url_root . '/' . $server_script . '?' . $params;

    print $log_file "$gff_filename: URL: $url\n";
    
    $request->uri($url);
    
    # create a user agent to send the request

    my $ua = LWP::UserAgent->new(
        timeout             => 9000,
        env_proxy           => 1,
        agent               => $0,
        cookie_jar          => HTTP::Cookies::Netscape->new(file => $cookie_jar),
        protocols_allowed   => [qw(http https)],
    );

    my $response = $ua->request($request);

    my $source_name = $args{gff_source};

    if ($response && $response->is_success) {

        my $gff = $response->decoded_content;

        if ($gff =~ /EnsEMBL2GFF/) {
            
            # Send data to zmap on STDOUT
            print $gff;

            
            # cache the result
            open my $cache_file_h, '>', $cache_file or die "Cannot write to cache file '$cache_file'; $!\n";
            print $cache_file_h $gff;
            close $cache_file_h or die "Error writing to '$cache_file'; $!";
            
            my $dbh = DBI->connect("dbi:SQLite:dbname=$session_dir/otter.sqlite", undef, undef, {
                RaiseError => 1,
                AutoCommit => 1,
                });
            my $sth = $dbh->prepare(
                q{ UPDATE otter_filter SET done = 1, failed = 0, gff_file = ?, process_gff = ? WHERE filter_name = ? }
            );
            $sth->execute($cache_file, $process_gff || 0, $args{'gff_source'});
            
            # zmap waits for STDOUT to be closed as an indication that all
            # data has been sent, so we close the handle now so that zmap
            # doesn't tell otterlace about the successful loading of the column
            # before we have the SQLite db updated and the cache file saved.
            close STDOUT or die "Error writing to STDOUT; $!";
        }
        else {
            die "Unexpected response for $source_name: $gff\n";
        }
    }
    elsif ($response) {
        
        my $res = $response->content;
        
        my $err_msg;
        
        if ($res =~ /ERROR: (.+)/) {
            $err_msg = $1;
        }
        elsif ($res =~ /The Sanger Institute Web service you requested is temporarily unavailable/) {
            my $code = $response->code;
            my $message = $response->message;
            $err_msg = "This Sanger web service is temporarily unavailable: status = ${code} ${message}";
        }
        else {
            $err_msg = $res;
        }
        
        die "Webserver error for $source_name: $err_msg\n";
    }
    else {
        die "No response for $source_name\n";
    }
}




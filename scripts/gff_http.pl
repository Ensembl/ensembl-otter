#!/usr/bin/perl

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use URI::Escape qw(uri_escape);

my $DEBUG   = 1;
my $LOG     = 1;

my %args = map { split(/=/) } @ARGV;

# pull off arguments meant for us

my $url_root        = delete $args{url_root};
my $server_script   = delete $args{server_script};
my $session_dir     = delete $args{session_dir};
my $cookie_jar      = delete $args{cookie_jar};

my $log_file;
if ($LOG) {
    my $log_file_name = $session_dir.'/gff_log.txt';
    open $log_file, ">>$log_file_name";
}

# we always want to rebase for zmap

$args{rebase} = 1;

# concatenate the rest of the arguments into a parameter string

my $params = join '&', map { uri_escape($_).'='.uri_escape($args{$_}) } keys %args;

my $gff_filename;

if ($DEBUG) {
    $gff_filename = $args{gff_source}.'.gff';
}
else {
    $gff_filename = md5_hex($params).'.gff';
}

my $top_dir = $session_dir.'/gff_cache';

unless (-d $top_dir) {
    mkdir $top_dir or print STDERR "Failed to create toplevel cache directory: $!\n";
}

my $cache_file;

if ($DEBUG) {
    $cache_file = $top_dir.'/'.$gff_filename;
}
else {
    my $cache_dir = $top_dir.'/'.substr($gff_filename, 0, 2);
    unless (-d $cache_dir) {
        mkdir $cache_dir or print STDERR "Failed to create cache directory: $!\n";
    }
    $cache_file = $cache_dir.'/'.$gff_filename;
}

if (-e $cache_file) {
    # cache hit

    print $log_file "cache hit for $gff_filename\n" if $LOG;

    open my $gff_file, "<$cache_file" or print STDERR "Failed to open cache file: $!\n";

    while (<$gff_file>) {
        print;
    }
}
else {
    # cache miss
    
    # only require these packages now, so we don't take the import hit on a cache hit
    
    require LWP::UserAgent;
    require HTTP::Request;
    require HTTP::Cookies::Netscape;
    
    print $log_file "cache miss for $gff_filename\n" if $LOG;
    
    my $request = HTTP::Request->new;

    $request->method('GET');

    #$request->accept_decodable(HTTP::Message::Decodable);

    my $url = $url_root . '/' . $server_script . '?' . $params;

    print $log_file "URL: $url\n" if $LOG && $DEBUG;
    
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
            
            print $gff;
            
            # zmap waits for STDOUT to be closed as an indication that all
            # data has been sent, so we close the handle now so that zmap
            # can start processing the data while we create the cached copy

            close STDOUT;
            
            # cache the result
            open my $cache_file_h, ">$cache_file" or print STDERR "Failed to open cache file: $!\n";
        
            print $cache_file_h $gff;
        }
        else {
            print STDERR "Unexpected response for $source_name: $gff\n";
        }
    }
    elsif ($response) {
        
        my $res = $response->content;
        
        my $err_msg;
        
        if ($res =~ /ERROR: (.+)/) {
            $err_msg = $1;
        }
        elsif ($res =~ /The Sanger Institute Web service you requested is temporarily unavailable/) {
            $err_msg = "web service temporarily unavailable";
        }
        else {
            $err_msg = $res;
        }
        
        print STDERR "Webserver error for $source_name: $err_msg\n";
    }
    else {
        print STDERR "No response for $source_name\n";
    }
}




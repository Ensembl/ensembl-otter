#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::ConfigMetakeys;
use parent 'Bio::Otter::Utils::Script';

use Bio::Otter::Log::Log4perl qw(:easy);
use Net::hostent;
use Try::Tiny;

use Bio::Otter::Lace::Defaults;
use Bio::Otter::Source::Filter;
use Bio::Otter::Version;

sub ottscript_options {
    return (
        dataset_mode => 'one_or_all',
        no_aliases   => 1,
        );
}

sub ottscript_validate_args {
    my ($self, $opt, $args) = @_;

    $args ||= [];
    my $mode = shift @$args;
    $mode                          or $self->usage_error("<mode> must be specified");
    $mode =~ /^(check|gen_mk2rb)$/ or $self->usage_error('<mode> must be one of: check, gen_mk2rb');
    $self->mode($mode);

    return;
}

sub setup {
    my ($self) = @_;
    Bio::Otter::Log::Log4perl->easy_init;
    Bio::Otter::Lace::Defaults::do_getopt or die "do_getopt failed";
    $self->client->get_server_otter_config;
    return;
}

sub process_dataset {
  my ($self, $dataset) = @_;

  my $ds_name = $dataset->name;

  my $server_ds = $dataset->otter_sd_ds;
  my $client_ds = $self->client->get_DataSet_by_name($ds_name);
  $client_ds->load_client_config;

 FILTER: foreach my $filter ( @{$client_ds->filters}, $self->_core_filter ) {

      my $metakey = $filter->metakey;
      next unless $metakey;
      say sprintf "\t%s\t%s", $filter->name, $metakey if $self->verbose;

      my ($raw_hostname, $hostname);
      try {
          my $dba = $server_ds->satellite_dba($metakey);
          $raw_hostname = $dba->dbc->host;
          my $hostent = gethostbyname($raw_hostname);
          $hostname = $hostent->name;
      }
      catch {
          say STDERR "$ds_name:$metakey connection FAILED: $_";
      };
      next FILTER unless $hostname;
      say sprintf "\t\t%s\t%s\t(%s)", $metakey, $hostname, $raw_hostname if $self->verbose;
      $self->add_translation($ds_name, $metakey, $hostname) if $self->mode eq 'gen_mk2rb';
  }
  return;
}

# fake filter entry for pipeline_db_head
#
sub _core_filter {
    my ($self) = @_;
    my $_core_filter = $self->{'_core_filter'};
    return $_core_filter if $_core_filter;

    $_core_filter = Bio::Otter::Source::Filter->new;
    $_core_filter->name('core');
    $_core_filter->metakey('pipeline_db_head');

    return $self->{'_core_filter'} = $_core_filter;
}

{
    my %translations_by_metakey;

    sub add_translation {
        my ($self, $ds_name, $metakey, $hostname) = @_;
        my $translation = $translations_by_metakey{$metakey} ||= {};
        $translation->{$ds_name} = $hostname;
        if (exists $translation->{default}) {
            if (my $default_hostname = $translation->{default}) {
                unless ($hostname eq $default_hostname) {
                    say STDERR "WARNING: processing $ds_name - $metakey has differing resolutions: ",
                        join ',', grep {$_ ne 'default'} keys %$translation;
                    $translation->{default} = undef;
                }
            }
        } else {
            $translation->{default} = $hostname;
        }
        return;
    }

    sub finish {
        my ($self) = @_;
        return unless $self->mode eq'gen_mk2rb';

        # Pivot the hashes, putting metakeys into (in order of priority):
        #  - $ds_name if only a single dataset has that metakey
        #  - default  if in multiple datasets and identical in each
        #  - $ds_name if in multiple datasets and different in some

        my %translations_by_dataset;
        while (my ($metakey, $translation_by_mk) = each %translations_by_metakey) {

            if (scalar keys %$translation_by_mk == 2) { # default + just one dataset...
                delete $translation_by_mk->{default};   # ...so leave just the one
            }
            elsif (my $default = $translation_by_mk->{default}) {
                $translation_by_mk = { default => $default }; # identical, so use default
            } else {
                delete $translation_by_mk->{default}; # multiple, remove empty default key
            }
            while (my ($ds_name, $hostname) = each %$translation_by_mk) {
                my $translation_by_ds = $translations_by_dataset{$ds_name} ||= {};
                $translation_by_ds->{$metakey} = $hostname;
            }
        }

        my $version = Bio::Otter::Version->version;
        my $date    = localtime;
        say << "__EO_HEADER__";
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
#
# Autogenerated by   : config_metakeys gen_mk2rb
#               from : otter config for version $version
#               on   : $date
#
__EO_HEADER__

        $self->config_for('default', $translations_by_dataset{default});
        delete $translations_by_dataset{default};

        foreach my $ds_name (sort keys %translations_by_dataset) {
            $self->config_for($ds_name, $translations_by_dataset{$ds_name});
        }

        say << "__EO_FOOTER__";
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
__EO_FOOTER__

        return;
    }

    sub config_for {
        my ($self, $ds_name, $translations) = @_;
        say "[${ds_name}.metakey_to_resource_bin]";
        foreach my $metakey (sort keys %$translations) {
            say $metakey, "=", $translations->{$metakey};
        }
        say '';
        return;
    }
}

sub mode {
    my ($self, @args) = @_;
    ($self->{'mode'}) = @args if @args;
    my $mode = $self->{'mode'};
    return $mode;
}

sub client {
    my ($self) = @_;
    my $client = $self->{'client'};
    return $client if $client;
    $client = Bio::Otter::Lace::Defaults::make_Client;
    return $self->{'client'} = $client;
}

# End of module

package main;

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::ConfigMetakeys->import->run;

exit;

# EOF

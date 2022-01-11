=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

# Build a dummy AceDatabase object

package OtterTest::AceDatabase;

use strict;
use warnings;

use Try::Tiny;

use Bio::Otter::Log::WithContext;

use OtterTest::Client;

sub new_mock {
    my ($pkg) = @_;

    my $self = bless {}, $pkg;
    $self->Client(OtterTest::Client->new);

    return $self;
}

sub Client {
    my ($self, @args) = @_;
    ($self->{'Client'}) = @args if @args;
    my $Client = $self->{'Client'};
    return $Client;
}

sub logger {
    my ($self, $category) = @_;
    $category = scalar caller unless defined $category;
    return Bio::Otter::Log::WithContext->get_logger($category, name => 'OtterTest.AceDatabase');
}

# -------- perhaps this should be a different module? --------

sub new_from_slice_params {
    my ($pkg, $ace_home, $name, @slice_region_param_list) = @_;

    my $slicer = sub {
        my ($client) = @_;
        return Bio::Otter::Lace::Slice->new($client, @slice_region_param_list);
    };
    return $pkg->_new_from_slicer($ace_home, $name, $slicer);
}

sub new_from_region {
    my ($pkg, $ace_home, $name, $region) = @_;

    my $slicer = sub {
        my ($client) = @_;
        return Bio::Otter::Lace::Slice->new_from_region($client, $region);
    };
    return $pkg->_new_from_slicer($ace_home, $name, $slicer);
}

sub _new_from_slicer {
    my ($pkg, $ace_home, $name, $slicer) = @_;

    require Bio::Otter::Lace::AceDatabase;
    require Bio::Otter::Lace::Slice;

    # B:O:L:C new_AceDatabase
    my $client = OtterTest::Client->new;
    my $slice = $slicer->($client);
    my $adb = Bio::Otter::Lace::AceDatabase->new;
    $adb->Client($client);
    $adb->home($ace_home);

    # CW:SequenceNotes open_SequenceSet
    $adb->error_flag(0);
    $adb->make_database_directory;
    $adb->write_access(0);
    $adb->name($name);
    $adb->slice($slice);
    $adb->load_dataset_info;
    #
    # MCW:ColumnChooser load_filters
    try     { $adb->init_AceDatabase }
    catch   { die "init_AceDatabase failed: $_" }
    finally { $adb->error_flag(0) };

    return $adb;
}

1;

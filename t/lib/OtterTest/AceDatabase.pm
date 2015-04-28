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

sub new_with_slice {
    my ($pkg, $ace_home, $name, @slice_region_param_list) = @_;

    require Bio::Otter::Lace::AceDatabase;
    require Bio::Otter::Lace::Slice;

    # B:O:L:C new_AceDatabase
    my $client = OtterTest::Client->new;
    my $slice = Bio::Otter::Lace::Slice->new($client, @slice_region_param_list);
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

package Bio::Otter::Lace::DasClient;

use strict;
use warnings;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::Lace::DasClient::Locator;

my $DEBUG = 0;

sub new{
    my( $pkg ) = @_;
    
    my $self = bless {}, $pkg;
    $self->locators();
    return $self;
}
sub locators{
    my ($self) = @_;
    # can we get species here?  Don't think so
    my $species      = 'default';
    my $das_locators = Bio::Otter::Lace::Defaults::option_from_array([$species, qw( das locators )]) || {};
    foreach my $locator(keys(%$das_locators)){
        print STDERR "locator $locator is " . ($das_locators->{$locator} ? 'true' : 'false') . "\n" if $DEBUG;
        next unless $das_locators->{$locator};
        $self->_add_locatorObj($locator);
    }
}
sub locatorObjs{
    my ($self) = @_;
    return [ values(%{$self->{'_locatorObjs'}}) ];
}
sub _locator_by_url{
    my ($self, $url) = @_;
    return unless $url;
    return $self->{'_locatorObjs'}->{$url};
}
sub _add_locatorObj{
    my ($self, $locator) = @_;
    # can we get species here?
    my $species          = 'default';
    my $locator_options  = Bio::Otter::Lace::Defaults::option_from_array([$species, qw( das locator ), $locator]) || {};
    my $url              = $locator_options->{'url'};
    print STDERR "adding a locator with url: $url \n";
    return unless $url;  # can't get far without a url
    my $locObj;
    if(!$self->{'_locatorObjs'}->{$url}){ # need a new object
        $locObj = Bio::Otter::Lace::DasClient::Locator->new();
    }else{
        $locObj = $self->{'_locatorObjs'}->{$url};
    }
    foreach my $param(keys(%$locator_options)){
        my $value = $locator_options->{$param};
        if($locObj->can($param)){ # set the value 
            $locObj->$param($value);
        }else{
            warn "$locObj doesn't have method '$param'. Couldn't set it to '$value'. Check configuration.\n";
        }
    }

    # the locator object needs a method_object to display ace methods correctly.
    # this isn't really an otter requirement though.  Why should it go here?
    # anyway it's here for now
    # can Bio::Otter::Lace::Defaults::make_ace_methods() do what I want here?
    # It would then know a little more than a DasClient





    # add it to the cache of objects
    $self->{'_locatorObjs'}->{$url} = $locObj;
    return 1;
}

sub available_dsn{
    my ($self, $id) = @_;
    print STDERR "\t *** available_dsn called on " . ref($self) . " obj\n" if $DEBUG;
    my $locObjs = $self->locatorObjs();
    foreach my $locObj(@{$locObjs}){
        return "$locObj" if $locObj->available_dsn($id);
    }
    return 0;
}
sub list_DSN_for_url{
    my ($self, $url_or_dasObj) = @_;
    print STDERR "\t *** list_DSN_for_url called on " . ref($self) . " obj\n" if $DEBUG;
    my $url    = "$url_or_dasObj";
    my $locObj = $self->_locator_by_url($url);
    return $locObj->list_DSN();
}

1;


__END__

How it works

otter_config holds the key.

[Das locator] config stanza needs
# connection
url=http[s]://das.server[:port]/das
proxy_url=http[s]://proxy.server[:port]

selected_sources=dsn of sources required

# ace file creation
filterclass=name of the filter
method_tag=name of the method
method_group=group to put it in

# optional ? for interface
compulsory=[1|0]


Client
  -> creates DasClient
    -> adds locators setting filterclass, method_tag, method_group
    
AceDatabase
  -> gets DasClient
  -> makes a AceDataFactory
  -> finds locators and makes filter Obj, assigns method Obj and sets method_group [right priority]
  -> gets AceDataFactory
    -> ace_data_from_slice 
      -> DasClient fetches the das features and they make .ace files
  
=head1 EXAMPLE OTTER CONFIG


[client]
with-das=1
write_access=0
methods_files=/nfs/team71/analysis/rds/workspace/ace_skeleton/rawdata/methods.ace

[default.ensembl_sources]
ensembl_core_db=---ensembl
ensembl_estgene_db=---genomewise


[default.das.locators]
ensembl=0
development=1

[human.das.locators]
ensembl=1

[das.locator.ensembl]
url=
compulsory=1
selected_sources=

[default.das.locator.development]
#url=http://servlet.sanger.ac.uk:8080/das
#selected_sources=homo_sapiens_core_25_34e_cds
proxy_url=http://wwwcache.sanger.ac.uk:3128
compulsory=1
url=http://deskpro345.dynamic.sanger.ac.uk:8080/das
selected_sources=hsa35genes
method_tag=BLASTN
filterclass=Gene
method_group=predicted

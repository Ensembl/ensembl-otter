
package Bio::Otter::Lace::DasClient::Locator;

use strict;
use warnings;

my $DEBUG     = 1;
my $DEBUG_DAS = 1;
# new
sub new{
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

################################
# Simple Properties
################################
#
# These get set by the DasClient->add_Locator from the config file
sub url{
    my ($self, $arg) = @_;
    $self->{'_url'} = $arg if $arg;
    return $self->{'_url'};
}
sub proxy_url{
    my ($self, $arg) = @_;
    $self->{'_proxy_url'} = $arg if $arg;
    return $self->{'_proxy_url'};
}
sub protocol{
    my ($self, $arg) = @_;
    $self->{'_protocol'} = $arg if $arg;
    return $self->{'_protocol'};
}
sub compulsory{
    my ($self, $arg) = @_;
    $self->{'_compulsory'} = $arg if defined($arg);
    return $self->{'_compulsory'} ? 1 : 0;
}
# not sure these ace stuff should go here, but this locator is
# similar to CloneSequence.pm in that it has to exist to merge
# multiple das checkouts together.
sub method_tag{
    my $self = shift;
    my $methObj = $self->method_object();
    if($methObj){
        return $methObj->name(@_);
    }else{
        return $self->__method_tag(@_);
    }
}
sub __method_tag{
    my ($self, $meth) = @_;
    $self->{'_method_tag'} = $meth if $meth;
    return $self->{'_method_tag'} || '';
}
sub method_object{
    my ($self, $meth) = @_;
    $self->{'_method'} = $meth if $meth;
    return $self->{'_method'};
}

################
sub filterclass{
    my ($self, $f) = @_;
    $self->{'_filterclass'} = $f if $f;
    return $self->{'_filterclass'};
}

#################################
# methods
#################################
sub selected_sources{
    my ($self, $sources) = @_;
    print STDERR "\t *** selected_sources called on " . ref($self) . " obj\n" if $DEBUG;
    if($sources && ref($sources) eq 'ARRAY'){
        $self->{'_selected_sources'} = $sources;
    }elsif($sources && !ref($sources)){
        my $try = [ split ',', $sources ];
        $self->{'_selected_sources'} = $try;
    }
    if($sources && ref($self->{'_selected_sources'}) && @{$self->{'_selected_sources'}}){
        my $check = [];
        foreach my $source(@{$self->{'_selected_sources'}}){
            if ($self->available_dsn($source)){
                push(@$check, $source);
            }else{
                print STDERR "dsn '$source' isn't available here\n";
            }
        }
        $self->{'_selected_sources'} = $check;
    }
    return $self->{'_selected_sources'};
}
sub select_source{
    my ($self, $dsn) = @_;
    return unless $self->available_dsn($dsn);
    $self->{'_selected_sources'} ||= [];
    push(@{$self->{'_selected_sources'}}, $dsn);   
}
sub available_dsn{
    my ($self, $dsn_name) = @_;
    print STDERR "\t *** available_dsn called on " . ref($self) . " obj\n" if $DEBUG;
    my $dasObj = $self->get_DasObj();
    $self->{'_available_dsn'} ||= [];
    unless(@{$self->{'_available_dsn'}}){
        $self->{'_available_dsn'} = $dasObj->fetch_dsn_info();
    }
    foreach my $dsn (@{$self->{'_available_dsn'}}){
        warn "DSN: ", Data::Dumper::Dumper($dsn);
        return 1 if $dsn->id eq $dsn_name;
    }
    return 0;
}

sub list_DSN{
    my ($self) = @_;
    print STDERR "\t *** list_DSN called on " . ref($self) . " obj\n" if $DEBUG;
    my $dasObj = $self->get_DasObj();
    $self->{'_available_dsn'} ||= [];
    unless(@{$self->{'_available_dsn'}}){
        $self->{'_available_dsn'} = $dasObj->fetch_dsn_info();
    }
    return $self->{'_available_dsn'};
}

sub get_DasObj{
    my ($self) = @_;
    my $dasObj = $self->{'_dasObj'};
    unless($dasObj){
        my $url   = $self->url();
        my $proxy = $self->proxy_url();
        my $proto = $self->protocol()  || 'http';
        eval "
            require Bio::EnsEMBL::ExternalData::DAS::DASAdaptor;
            require Bio::EnsEMBL::ExternalData::DAS::DAS;
        ";
        if($@){
            die "Can't find a required module:\n$@\n";
        }
        print STDERR sprintf("url: '%s', proxy: '%s', proto: '%s'\n", $url, $proxy, $proto) if $DEBUG_DAS;
        my $dasAdapt = Bio::EnsEMBL::ExternalData::DAS::DASAdaptor->new(-url       => $url,
                                                                        -protocol  => $proto,
                                                                        -proxy_url => $proxy,
                                                                        );
        $dasAdapt->_db_handle->debug($DEBUG_DAS);
        $dasObj  = Bio::EnsEMBL::ExternalData::DAS::DAS->new($dasAdapt);
        $self->{'_dasObj'} = $dasObj;
    }
    return $dasObj;
}

1;

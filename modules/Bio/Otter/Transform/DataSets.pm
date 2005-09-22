package Bio::Otter::Transform::DataSets;

use strict;
use warnings;
use Bio::Otter::Transform;
use Bio::Otter::Lace::DataSet;

our @ISA = qw(Bio::Otter::Transform);


# probably these should be global rather than assign EVERY time
# ones were interested in
my $SUB_ELE = {
    map { $_ => 1 }
      qw(host port user pass dbname type
      dna_host dna_port dna_user dna_pass dna_dbname)
};
my $SUP_ELE = { map { $_ => 1 } qw(otter datasets) };

# this should be in xsl and use xslt to transform and create the objects
sub start_handler{
    my $self = shift;
    my $xml  = shift;
    my $ele  = shift;
    $ele     =~ tr/[A-Z]/[a-z]/;
    my $attr = {@_};
    $self->_check_version(@_) if $ele eq 'otter';

    if($ele eq 'dataset'){
        my $ds = Bio::Otter::Lace::DataSet->new();
        $ds->name($attr->{'name'});
        $ds->author($self->get_property('author'));
        $self->add_object($ds);
    }elsif($SUB_ELE->{$ele}){
     #   print "* Interesting $ele\n";
    }else{
      #  print "Uninteresting $ele\n";
    }
    
}
sub end_handler{ }
sub char_handler{
    my $self = shift;
    my $xml  = shift;
    my $data = shift;
    #my $context = ($xml->context)[-1];
    my $context = $xml->current_element();
    #print "context '$context'\n";
    if($SUB_ELE->{$context}){
        $context =~ tr/[a-z]/[A-Z]/;
        my $context_method = $context;
        my $ds = $self->objects;
        my $current = $ds->[$#$ds];
        if($current->can($context_method)){
            $current->$context_method($data);
        }
    }
}

sub sorted_objects {
    my $self = shift;
    
    return [sort {$a->name cmp $b->name} @{$self->objects}];
}

1;

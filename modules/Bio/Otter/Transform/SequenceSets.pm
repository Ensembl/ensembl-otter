package Bio::Otter::Transform::SequenceSets;

use strict;
use warnings;
use Bio::Otter::Transform;
use Bio::Otter::Lace::SequenceSet;

our @ISA = qw(Bio::Otter::Transform);


# ones were interested in 
my $SUB_ELE = { map { $_ => 1 } qw(description assembly_type vega_set_id analysis_priority)};
# super elements to the actual sequence set
my $SUP_ELE = { map { $_ => 1 } qw(otter sequencesets) };

# this should be in xsl and use xslt to transform and create the objects
sub start_handler{
    my $self = shift;
    my $xml  = shift;
    my $ele  = lc shift;
    my $attr = {@_};

    if($ele eq 'sequenceset'){
        my $ss = Bio::Otter::Lace::SequenceSet->new();
        $ss->name($attr->{'name'});
        $ss->is_hidden($attr->{'hidden'});
        $ss->dataset_name($self->get_property('dataset_name'));
        $self->add_object($ss);
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
        my $context_method = $context;
        my $ss = $self->objects;
        my $current = $ss->[$#$ss];
        if($current->can($context_method)){
            $current->$context_method($data);
        }else{
            print STDERR "$current can't $context_method\n";
        }
    }
}



1;

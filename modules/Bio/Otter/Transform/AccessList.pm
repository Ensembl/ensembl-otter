package Bio::Otter::Transform::AccessList;

use strict;
use warnings;
use Bio::Otter::Transform;

our @ISA = qw(Bio::Otter::Transform);

# ones were interested in 
my $SUB_ELE = { map { $_ => 1 } qw(author sequenceset_name access_type )};
# super elements to the actual sequence set
my $SUP_ELE = { map { $_ => 1 } qw(otter dataset accesslist) };
my $author;
my $sequenceset_name;

# this should be in xsl and use xslt to transform and create the objects
sub start_handler{
    my $self = shift;
    my $xml  = shift;
    my $ele  = lc shift;
    my $attr = {@_};
    $self->_check_version(@_) if $ele eq 'otter';
    if($ele eq 'accesslist'){
      my $dsObj=$self->get_property('dataset_object');
      $dsObj->{'_sequence_set_access_list'}={};
      $self->add_object($dsObj);
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
    my $context = $xml->current_element();
    if($SUB_ELE->{$context}){
      my $ss = $self->objects;
      my $current=$ss->[$#$ss];
      my $ssal=$current->{'_sequence_set_access_list'};
      if ($context eq 'author') {
	$author=$data;
	if (! defined $ssal->{$author}){
	  $ssal->{$author}={};
	}
      }
      if ($context eq 'sequenceset_name') {
	$sequenceset_name=$data;
	$ssal->{$author}->{$sequenceset_name}='';
      }
      if ($context eq 'access_type') {
	$ssal->{$author}->{$sequenceset_name}=$data;
      }
      $current->{'_sequence_set_access_list'}=$ssal;

    }
  }

1;
__END__

=head1 NAME - AccessList.pm


=head1 DESCRIPTION

XML Parsing for sequence set access list. Parses xml file and sets sequence setaccess list for DataSet Object

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

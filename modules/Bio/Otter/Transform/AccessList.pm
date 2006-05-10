package Bio::Otter::Transform::AccessList;

use strict;
use warnings;
use Bio::Otter::Transform;
use Bio::Otter::Lace::Access;

our @ISA = qw(Bio::Otter::Transform);

# ones were interested in 
my $SUB_ELE = { map { $_ => 1 } qw(author sequenceset_name access_type )};
# super elements to the actual sequence set
my $SUP_ELE = { map { $_ => 1 } qw(otter dataset accesslist) };
my $value;

# this should be in xsl and use xslt to transform and create the objects
sub start_handler{
    my $self = shift;
    my $xml  = shift;
    my $ele  = lc shift;
    my $attr = {@_};
    $value='';
    $self->_check_version(@_) if $ele eq 'otter';
    if($ele eq 'access'){
      my $al = Bio::Otter::Lace::Access->new();
      $self->add_object($al);
    }elsif($SUB_ELE->{$ele}){
     #   print "* Interesting $ele\n";
    }else{
      #  print "Uninteresting $ele\n";
    }
  }

sub end_handler{
    my $self = shift;
    my $xml  = shift;
    $value =~ s/^\s*//;
    $value =~ s/\s*$//;
    my $context = shift;
    if($SUB_ELE->{$context}){
        my $context_method = $context;
        my $cs = $self->objects;
        my $current = $cs->[$#$cs];
        if($current->can($context_method)){
            $current->$context_method($value);
        }else{
            print STDERR "$current can't $context_method\n";
        }
    }
 }

sub char_handler{
  my $self = shift;
  my $xml  = shift;
  my $data = shift;
  if ($data ne ""){
    $value .= $data;
  }
}

1;
__END__

=head1 NAME - AccessList.pm


=head1 DESCRIPTION

XML Parsing for sequence set access list. Parses xml file and sets sequence setaccess list for DataSet Object

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

package Bio::Vega::Evidence;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base 'Bio::EnsEMBL::Storable';

sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($name,$type)  = rearrange([qw(
												NAME
												TYPE
											  )],@args);

  $self->name($name);
  $self->type($type);
  return $self;
}

sub name {
  my ($obj,$value) = @_;
  if( defined $value) {
	 $obj->{'name'} = $value;
  }
  return $obj->{'name'};
}

sub type{
  my ($obj,$value) = @_;
  if( defined $value) {
	 if ($value eq 'ncRNA' || $value eq 'EST' || $value eq 'Protein' || $value eq 'cDNA' || $value eq 'Genomic' || $value eq 'UNKNOWN') {
	   $obj->{'type'} = $value;
	 } else {
	   $obj->throw("Invalid type [$value]. Must be one of EST,ncRNA,Protein,cDNA,Genomic");
	 }
  }
  return $obj->{'type'};
}


=head2 toString

 Title   : toString
 Usage   :
 Function:
 Example :
 Returns :
 Args    :


=cut

sub toString {
    my ($self, @args) = @_;

    my $str = "";
    if (scalar(@args) == 0) {
        push(@args, $self);
    }
    foreach my $arg (@args) {
        if ($arg->isa("Bio::Otter::Evidence")) {
            my $dbID   = "";
            my $infoid = "";

            if (defined($arg->dbID)) {
                $dbID = $arg->dbID;
            }
            if (defined($arg->transcript_info_id)) {
                $infoid = $arg->transcript_info_id;
            }
            $str = $str . "DbID                : " . $dbID . "\n";
            $str = $str . "Name                : " . $arg->name . "\n";
            $str = $str . "Transcript info id  : " . $infoid . "\n";
            $str = $str . "Type                : " . $arg->type . "\n";
        }
        else {
            $self->throw(
                "Can't print string if object not Evidence.  Currently [$arg]\n"
            );
        }
    }
    return $str;

}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


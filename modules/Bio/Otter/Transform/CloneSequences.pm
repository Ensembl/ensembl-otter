package Bio::Otter::Transform::CloneSequences;

use strict;
use warnings;
use Bio::Otter::Transform;
use Bio::Otter::Lace::CloneSequence;
# use Bio::Otter::Lace::Chromosome;

our @ISA = qw(Bio::Otter::Transform);

# ones were interested in 
my $SUB_ELE = { map { $_ => 1 } qw(clone_name accession sv chromosome chr_start chr_end contig_id contig_name length contig_start contig_end contig_strand super_contig_name )};
# super elements to the actual clonesequence
my $SUP_ELE = { map { $_ => 1 } qw(otter dataset sequenceset clonesequences clonesequence) };
my $chr;
my %id_chr;
my $value;

# this should be in xsl and use xslt to transform and create the objects
sub start_handler{
    my $self = shift;
    my $xml  = shift;
    my $ele  = lc shift;
    my $attr = {@_};
    $value='';
    $self->_check_version(@_) if $ele eq 'otter';
    if($ele eq 'clonesequence'){
      my $cl = Bio::Otter::Lace::CloneSequence->new();
      $self->add_object($cl);
    }
    if($ele eq 'chr'){
      my $cs=$self->objects;
      my $cl=$cs->[$#$cs];

      # my $ch = Bio::Otter::Lace::Chromosome->new();
      # $ch->name($attr->{'name'});
      # $ch->length($attr->{'length'});
      # $cl->chromosome($ch);

        # from now on, just keep the chromosome's name
      $cl->chromosome($attr->{name});
    }
    if($ele eq 'lock'){
      my $authorObj = Bio::Otter::Author->new(-dbid  => $attr->{'author_id'},
					      -name  => $attr->{'author_name'},
					      -email => $attr->{'email'});
      my $cloneLock = Bio::Otter::CloneLock->new(-author   => $authorObj,
						 -hostname => $attr->{'host_name'},
						 -dbID     => $attr->{'lock_id'});
      my $cs = $self->objects;
      my $cl = $cs->[$#$cs];
      $cl->set_lock_status($cloneLock);

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

=head1 NAME - CloneSequences.pm


=head1 DESCRIPTION

XML Parsing for Clone Sequences. Parses xml file and converts to CloneSequence Objects

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

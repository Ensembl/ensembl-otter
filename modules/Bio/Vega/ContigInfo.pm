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

package Bio::Vega::ContigInfo;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base qw(Bio::EnsEMBL::Storable);


sub new {
    my ($class, @args) = @_;

    my $self = bless {}, $class;
    my ($adaptor, $dbID, $slice, $author, $attributes, $created_date )  =
        rearrange([qw( ADAPTOR dbID SLICE AUTHOR ATTRIBUTES CREATED_DATE )], @args);

    $self->dbID($dbID)                      if $dbID;
    $self->adaptor($adaptor)                if $adaptor;

    $self->slice($slice)                    if $slice;
    $self->author($author)                  if $author;
    $self->add_Attributes(@$attributes)     if $attributes;
    $self->created_date($created_date)      if $created_date;

    return $self;
}

sub slice {
    my ($self, $slice) = @_;

    if($slice) {
        if(!ref($slice) || !$slice->isa('Bio::EnsEMBL::Slice')) {
            $self->throw('slice argument must be a Bio::EnsEMBL::Slice');
        }
        $self->{'slice'} = $slice;
    }
    return $self->{'slice'};
}

sub author {
    my ($self, $author) = @_;

    if($author) {
        if(!ref($author) || !$author->isa('Bio::Vega::Author')) {
            $self->throw("Argument is not a Bio::Vega::Author");
        }
        $self->{'author'} = $author;
    }
    return $self->{'author'};
}

    # created_date is only set for contig_info objects that either come directly
    # from the DB or have just been stored.
    # Since the date is not a part of XML, the XML->Vega parser will leave the created_date unset.
    #
sub created_date  {
    my ($self, @args) = @_;

    $self->{'created_date'} = shift @args if scalar(@args);

    return $self->{'created_date'};
}

sub add_Attributes {
    my ($self, @attrib_list) = @_;

    my $al = $self->{'attributes'} ||= [];

    foreach my $attrib ( @attrib_list ) {
        if (! $attrib->isa('Bio::EnsEMBL::Attribute')) {
            $self->throw( "Argument to add_Attribute has to be a Bio::EnsEMBL::Attribute" );
        }
        push( @$al, $attrib );
    }

    return;
}

sub vega_hashkey_sub {
    my ($self) = @_;
    my $attributes = $self->get_all_Attributes;
    my $hashkey_sub={};
    foreach my $a (@$attributes) {
        $hashkey_sub->{$a->value}=1;
    }
    return $hashkey_sub;
}

sub vega_hashkey {
    my ($self) = @_;

    return lc scalar @{$self->get_all_Attributes};
}

sub get_all_Attributes  {
  my ($self, $attrib_code) = @_;
  if( ! exists $self->{'attributes' } ) {
    if(!$self->adaptor() ) {
      return [];
    }

    my $attribute_adaptor = $self->adaptor();
    $self->{'attributes'} = $attribute_adaptor->fetch_all_by_ContigInfo($self);
  }
  if( defined $attrib_code ) {
    my @results = grep { uc($_->code()) eq uc($attrib_code) }
    @{$self->{'attributes'}};
    return \@results;
  } else {
    return $self->{'attributes'};
  }

}

1;

__END__

=head1 NAME - Bio::Vega::ContigInfo.pm

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


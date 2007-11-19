package Bio::Vega::DBSQL::TranslationAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Vega::Translation;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use base 'Bio::EnsEMBL::DBSQL::TranslationAdaptor';

### This module is not used any more.
### We take care of this in Bio::Vega::Transcript::reincarnate_transcript() instead

sub fetch_by_stable_id  {

  my ($self, $stable_id) = @_;
  my ($translation) = $self->SUPER::fetch_by_stable_id($stable_id);
  if ($translation){
	 bless $translation, "Bio::Vega::Translation";
  }
  return $translation;

}

sub fetch_by_stable_id_version  {

  my ($self, $stable_id, $version) = @_;

  my $constraint = "tsi.stable_id = '$stable_id' AND tsi.version = $version ORDER BY tsi.modified_date DESC, tsi.translation_id DESC LIMIT 1";
  my ($translation) = @{ $self->generic_fetch($constraint) };

  return $translation;

}

sub fetch_by_Transcript  {
  my ( $self, $transcript ) = @_;
  my ($translation) = $self->SUPER::fetch_by_Transcript($transcript);
  if ($translation){
	 bless $translation, "Bio::Vega::Translation";
  }
  return $translation;
}

1;


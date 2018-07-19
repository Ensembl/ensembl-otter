package Bio::Otter::Server::UserSpecies;

use strict;
use warnings;
use DBI;

sub species_group{

 # MySQL database configurations
 my $dsn = "DBI:mysql:otter_registration";
 my $username = "****";
 my $password = '****';

 # Connect to MySQL database
 my $dbh = DBI->connect($dsn,$username,$password);
 
 # Set up hash of species for each user
 my %final_species_groups = query_links($dbh);

 $final_species_groups{'species_groups'}{'dev'} = ['human_dev', 'human_test'];
 $final_species_groups{'species_groups'}{'main'} = ['c_elegans', 'cat', 'chicken', 'chimp', 'cow', 'dog', 'drosophila', 'gibbon', 'gorilla', 'human', 'lemur', 'marmoset', 'medicago', 'mouse', 'mus_spretus', 'opossum', 'pig', 'platypus', 'rat', 'sheep', 'sordaria', 'tas_devil', 'tomato', 'tropicalis', 'wallaby', 'zebrafish']; 
 $final_species_groups{'species_groups'}{'mouse_strains'} = ['mouse-SPRET-EiJ', 'mouse-PWK-PhJ', 'mouse-CAST-EiJ', 'mouse-WSB-EiJ', 'mouse-NZO-HlLtJ', 'mouse-C57BL-6NJ', 'mouse-NOD-ShiLtJ', 'mouse-FVB-NJ', 'mouse-DBA-2J', 'mouse-CBA-J', 'mouse-C3H-HeJ', 'mouse-AKR-J', 'mouse-BALB-cJ', 'mouse-A-J', 'mouse-LP-J', 'mouse-129S1-SvImJ', 'mouse-C57BL-6NJ_v1_test'];
 $final_species_groups{'species_groups'}{'restricted'} =['human_dev','human_test','mouse_test'];

 # Disconnect from the MySQL database
 $dbh->disconnect();
 return \%final_species_groups;
}

sub query_links{ 
 my ($dbh) = @_;
 my %data_group;
 
  #Query the database
  my $sql_user_group = "SELECT username, species_write, species_read FROM otter_user";
  my $sth_user_group = $dbh->prepare($sql_user_group);
  $sth_user_group->execute();
  while(my $array_ref = $sth_user_group->fetchrow_arrayref()){
        my @temp_array_write = ();
        my @temp_array_read = ();

        #Setting up read and write species for each user
        my $username = $array_ref->[0];
        my $species_write_string = $array_ref->[1];  
        my @species_write_array = split ',', $species_write_string; 
        my $species_read_string = $array_ref->[2];  
        my @species_read_array = split ',', $species_read_string; 
        $data_group{'user_groups'}{$username.'.data'}{'users'} = $username; 
        $data_group{'user_groups'}{$username.'.data'}{'write'} = \@species_write_array;
#        $data_group{'user_groups'}{$username.'.data'}{'read'} = \@species_read_array; #Uncomment this line when READONLY datasets are available
  }

  $sth_user_group->finish();            

  return %data_group;      
  
}

1;

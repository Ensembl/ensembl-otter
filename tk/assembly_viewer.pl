#!/usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

=head1 NAME

assembly_viewer.pl

=head1 SYNOPSIS

assembly_viewer.pl

=head1 DESCRIPTION

This is a Tk-based tool to visualize the mapping data between two sets of chromosome assembly, the reference and alternative chromosomes.
If the login, password and port parameters of the loutre connexion are not provided, they will be
recovered from the ~/.netrc file. See the Net::Netrc module for more details.


=head1 OPTIONS

    -host   (default: otterlive)        host name for the loutre database (gets put as phost= in locator)
    -dbname (no default)               for RDBs, what name to connect to (pname= in locator)
    -user   (check the ~/.netrc file)  for RDBs, what username to connect as (puser= in locator)
    -pass   (check the ~/.netrc file)  for RDBs, what password to use (ppass= in locator)
    -port   (check the ~/.netrc file)  for RDBs, what port to use (pport= in locator)

    -ref_chr|ref          list of reference chromosome name
    -alt_chr|alt          (optional) list of alternative chromosome name
    -ref_cs_name|rcn      (default: chromosome) name of the reference coordinate system
    -ref_cs_version|rcv   (default: Otter) version of the reference coordinate system
    -alt_cs_name|acn      (default: chromosome) name of the alternative coordinate system
    -alt_cs_version|acv   (default: Otter) version of the alternative coordinate system
    -height				  (default:800) height of the central canvas
    -width				  (default:1000) width of the central canvas
    -help|h               displays this documentation with PERLDOC

=head1 EXAMPLES

Here are some command line examples:

assembly_viewer.pl -dbname loutre_human -ref chr13-12 -alt chr13-13 -rcv OtterArchive

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use Getopt::Long;
use Net::Netrc;
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use GeneHist::DataUtils qw(process_query);
use POSIX 'ceil';
use Tk;

# loutre connexion parameters, default values.
my $host = 'otterlive';
my $port = '';
my $name = '';
my $user = '';
my $pass = '';
my ( $r_cs_name, $r_cs_version ) = ( 'chromosome', 'Otter' );
my ( $a_cs_name, $a_cs_version ) = ( 'chromosome', 'Otter' );
my @ref_chr;
my @alt_chr;
my ( $AXIS_WIDTH, $C_HEIGHT, $C_WIDTH ) = ( 40, 800, 1000 );

my $usage = sub { exec( 'perldoc', $0 ); };
&GetOptions(
			 'host:s'               => \$host,
			 'port:n'               => \$port,
			 'dbname:s'             => \$name,
			 'user:s'               => \$user,
			 'pass:s'               => \$pass,
			 'rcn|ref_cs_name:s'    => \$r_cs_name,
			 'rcv|ref_cs_version:s' => \$r_cs_version,
			 'acn|alt_cs_name:s'    => \$a_cs_name,
			 'acv|alt_cs_version:s' => \$a_cs_version,
			 'ref|ref_chr=s'        => \@ref_chr,
			 'alt|alt_chr=s'        => \@alt_chr,
			 'height=s'				=> \$C_HEIGHT,
			 'width=s'				=> \$C_WIDTH,
			 'h|help!'              => $usage
  )
  or $usage->();
@ref_chr = split( /,/, join( ',', @ref_chr ) );
@alt_chr = split( /,/, join( ',', @alt_chr ) );
throw("Need a loutre (or Ensembl V.20+) database name") unless $name;
throw("No reference chromosome given")                  unless (@ref_chr);

if ( !$user || !$pass || !$port ) {
	my @param = &get_db_param($host);
	$user = $param[0] unless $user;
	$pass = $param[1] unless $pass;
	$port = $param[2] unless $port;
}
my $dba = Bio::Vega::DBSQL::DBAdaptor->new(
											   -user   => $user,
											   -dbname => $name,
											   -host   => $host,
											   -port   => $port,
											   -pass   => $pass
);
my $slice_adaptor = $dba->get_SliceAdaptor;
my $zoom_scale;
my $sequence_scale;
my $hash_coords_equiv;
my $select       = qq(
  SELECT sr2.name,a.*
  FROM assembly a, seq_region sr1, seq_region sr2,
       coord_system cs1, coord_system cs2
  WHERE a.asm_seq_region_id = sr1.seq_region_id
  AND a.cmp_seq_region_id = sr2.seq_region_id
  AND sr1.coord_system_id = cs1.coord_system_id
  AND sr2.coord_system_id = cs2.coord_system_id
  AND cs1.name IN ('$r_cs_name')
  AND cs2.name IN ('$a_cs_name')
  AND cs1.version = '$r_cs_version'
  AND cs2.version = '$a_cs_version'
  AND sr1.name = ?
  AND sr2.name LIKE ?
  ORDER BY sr2.name,a.asm_start
);
my $dbh        = $dba->dbc->db_handle;
my $sth_select = $dbh->prepare($select);

my $i            = 0;
my $element_strings = [];
my $c;
my @colors = ('blue','DarkGreen','SkyBlue','cyan','SaddleBrown','ivory4','green1','tan1','orange1');

for my $index ( 0 .. scalar(@ref_chr) - 1 ) {
	my $R_chr           = $ref_chr[$index];
	my $assembly;
	my @A_chrs = ();
	print STDOUT "Get assembly mapping for $R_chr\n";
	my $A_chr_name = @alt_chr ? $alt_chr[$index] : '%';
	$sth_select->execute( $R_chr, $A_chr_name );
	while ( my $r = $sth_select->fetchrow_hashref ) {
		$assembly->{ $r->{'name'} } ||= [];
		push @{ $assembly->{ $r->{'name'} } }, $r;
	}
	@A_chrs =
	  sort { scalar @{ $assembly->{$b} } <=> scalar @{ $assembly->{$a} } }
	  keys %$assembly;

	# fetch chromosome slices
	my $R_slice =
	  $slice_adaptor->fetch_by_region( $r_cs_name, $R_chr, undef, undef, undef,
									   $r_cs_version );
	throw("Reference slice $R_chr:$r_cs_name:$r_cs_version cannot be found!") unless $R_slice;
	throw("No mapping between $R_chr and alternative $a_cs_name:$a_cs_version in $name") unless @A_chrs;
	my $total_alt_length = 0;
	foreach my $A_chr (@A_chrs) {
		my $A_slice =
		  $slice_adaptor->fetch_by_region( $a_cs_name, $A_chr, undef,undef,
										   undef, $a_cs_version );
		$total_alt_length += $A_slice->length;
		throw("Alternative slice $A_chr:$a_cs_name:$a_cs_version cannot be found!") unless $A_slice;
	}
	my $ref_length = $R_slice->length;
	printf "%22s  %10d bp\n", $R_slice->name, $R_slice->length;
	my $title =
	  "Assembly Viewer: Reference $R_chr:$r_cs_version <=> Alternative "
	  . join( "/", @A_chrs )
	  . ":$a_cs_version";

	## Create the Tk widgets here

	my $mw = MainWindow->new(-title => $title);
	my $font = $mw->fontCreate(-family=>'helvetica', -size=>9);

	&get_canvas_window($mw);

	my $zoom_frame   = $mw->Frame()->pack();
	my $ref_frame   = $mw->Frame()->pack();
	my $alt_frame   = $mw->Frame()->pack();
	my $align_frame = $mw->Frame()->pack();


	$zoom_frame->Label(
					   -text    => 'ZOOM X',
					   -anchor  => 'w',
					   -justify => 'left',
					   -width   => 7,
					   -font	=> $font
	)->pack( -side => 'left' );

	$zoom_frame->Label(
					   -textvariable    => \$zoom_scale,
					   -anchor  => 'w',
					   -justify => 'left',
					   -width   => 10,
					   -font	=> $font
	)->pack( -side => 'left' );

	my $ref_txt;
	$ref_frame->Label(
					   -text    => 'Reference object (x-axis)',
					   -anchor  => 'w',
					   -justify => 'left',
					   -width   => 30,
					   -font	=> $font
	)->pack( -side => 'left' );
	my $ref_entry = $ref_frame->Entry(
									   -readonlybackground   => 'white',
									   -justify      => 'left',
									   -relief       => 'sunken',
									   -state        => 'readonly',
									   -takefocus    => 0,
									   -textvariable => \$ref_txt,
									   -width        => 100,
					   					-font	=> $font
	)->pack( -side => 'right' );
	my $alt_txt;
	$alt_frame->Label(
					   -text    => 'Alternative object (y-axis)',
					   -anchor  => 'w',
					   -justify => 'left',
					   -width   => 30,
					   -font	=> $font
	)->pack( -side => 'left' );
	my $alt_entry = $alt_frame->Entry(
									    -readonlybackground   => 'white',
									   -justify      => 'left',
									   -relief       => 'sunken',
									   -state        => 'readonly',
									   -takefocus    => 0,
									   -textvariable => \$alt_txt,
									   -width        => 100,
					   				   -font	=> $font
	)->pack( -side => 'right' );
	my $align_txt;
	$align_frame->Label(
						 -text    => 'Alignment block',
						 -anchor  => 'w',
						 -justify => 'left',
						 -width   => 30,
					     -font	=> $font
	)->pack( -side => 'left' );
	my $align_entry = $align_frame->Entry(
										    -readonlybackground   => 'white',
										   -justify      => 'left',
										   -relief       => 'sunken',
										   -state        => 'readonly',
										   -takefocus    => 0,
										   -textvariable => \$align_txt,
										   -width        => 100,
					   						-font	=> $font

	)->pack( -side => 'right' );

	my $query_f = $mw->Frame(-relief => 'groove', -borderwidth => 1)
    	-> pack(-side=>'top', -fill=>'x');

  	$query_f->Label(-text=>'Search and display (gene / transcript stable id or gene name / transcript name) ',
					   -font	=> $font)
    	-> pack(-side=>'left');
  	my $query;
  	my $entry1 = $query_f->Entry(-textvariable=>\$query, -width=>25, -bg=>'white',
					   -font	=> $font)
  		->pack(-side=>'left');
  	# reset
  	$query_f->Button(-text=>'Clear', -font=>$font, -command=>sub {$entry1->delete('0.0', 'end')})
  		->pack(-side => 'left');
  	my $gene_lb = $query_f->Scrolled('Listbox',-bg=>'white', -scrollbars => 'e', -selectmode => 'single',-height => 3, -width => 30,
					   -font	=> $font)->
  		pack(-side=> 'left');

	$query_f->Button(-text=>'Submit',
					   -font	=> $font, -command => [ \&get_gene_objects, $dba, $entry1, $query_f,$gene_lb,$R_chr,$A_chrs[0]] )
		->pack(-side=>'right');

	## Start the drawing here

	$sequence_scale = $R_slice->length / $C_WIDTH;
	$zoom_scale   	= 1;
	my $x           = $ref_length / $sequence_scale;
	my $y           = $total_alt_length / $sequence_scale;
	my @box         = ( 0, 0, $x, $y );
	my @top_box     = ( 0, 0, $x, $AXIS_WIDTH );
	my @left_box    = ( 0, 0, $AXIS_WIDTH, $y );
	my $canvas      = $mw->{_central_canvas};
	my $top_canvas  = $mw->{_top_canvas};
	my $left_canvas = $mw->{_left_canvas};
	&chr2canvas($R_chr,$top_canvas,0);
	$canvas->configure(    -bg           => 'white',
						-scrollregion => \@box, );
	$top_canvas->configure(    -bg           => 'white',
							-scrollregion => \@top_box, );
	$left_canvas->configure(    -bg           => 'white',
							 -scrollregion => \@left_box, );
	$canvas->configure( -closeenough => 2 );
	my @R_components = @{ $R_slice->project('contig') };
	my $axis_offset  = $AXIS_WIDTH / 2;
	my $chr_offset   = 0;

	foreach my $A_chr (@A_chrs) {
		&chr2canvas($A_chr,$left_canvas,$chr_offset);
		my $A_slice =
		  $slice_adaptor->fetch_by_region( $a_cs_name, $A_chr, undef,undef,
										   undef, $a_cs_version );
		my $alt_length = $A_slice->length;
		my ( $x1, $y1 ) = ( 0, $chr_offset / $sequence_scale );
		my ( $x2, $y2 ) =
		  ( $ref_length / $sequence_scale, ( $alt_length + $chr_offset ) / $sequence_scale );

		$canvas->createLine( $x1, $y2, $x2, $y2, -fill => 'green',tags => ['scale'] );
		$canvas->createLine( $x2, $y1, $x2, $y2, -fill => 'green',tags => ['scale'] );

		$top_canvas->createLine( $x2, $y1 + $axis_offset,
								 $x2, $y2, -fill => 'green',
								 tags => ['scale'] );
		$left_canvas->createLine( $x1 + $axis_offset,
								  $y2, $x2, $y2, -fill => 'green',
								  tags => ['scale'] );

		# draw the axis in green
		$top_canvas->createLine( $x1, $y1 + $axis_offset,
								 $x2,
								 $y1 + $axis_offset,
								 -fill => 'green',
								 tags => ['scale'] );
		$left_canvas->createLine( $x1 + $axis_offset,
								  $y1, $x1 + $axis_offset,
								  $y2, -fill => 'green',
								  tags => ['scale'] );
		printf "%22s  %10d bp\n", $A_slice->name, $alt_length;
		$dba->get_AssemblyMapperAdaptor()->delete_cache();
		my @A_components = @{ $A_slice->project('contig') };
		foreach my $A_seg (@A_components) {
			my $A_component = $A_seg->to_Slice;
			my $sr_name     = $A_component->seq_region_name;
			my $sr_start    = $A_component->start;
			my $sr_end      = $A_component->end;
			my $strand      = $A_component->strand;
			my $chr_start   = $A_seg->from_start;
			my $chr_end     = $A_seg->from_end;
			my $color       = $i % 2 ? 'black' : 'red';
			$element_strings->[$i] =
			  $A_chr . " "
			  . join( ":", $sr_name, $strand, $chr_start, $chr_end );
			my @pos = map $_ / $sequence_scale,
			  (
				$axis_offset * $sequence_scale,
				$chr_start - 1 + $chr_offset,
				$axis_offset * $sequence_scale,
				$chr_end + $chr_offset,
			  );
			my $position = $strand == -1 ? 'first' : 'last';
			$left_canvas->createLine(
												 @pos,
												 -width => 1,
												 -fill  => $color,
												 -tags  => [ 'alt_contig', $i ],
												 -arrow => $position
			);
			$i++;
		}

		# initialize a data structure that store a 2-way coordinates mapping
		# between ref and alt chromosomes. This will be used to zoom in/out to
		# the right area when a transcript is selected
		$hash_coords_equiv->{$A_chr}->{$R_chr} = [];
		$hash_coords_equiv->{$A_chr}->{'length'} = $alt_length;
		$hash_coords_equiv->{$R_chr}->{$A_chr} = [];
		$hash_coords_equiv->{$R_chr}->{'length'} = $ref_length;

		foreach my $r ( @{ $assembly->{$A_chr} } ) {
			my $ori = $r->{'ori'};
			my $X_1 = $r->{'asm_start'} ;
			my $X_2 = $r->{'asm_end'} ;
			my $Y_1 = $r->{'cmp_start'} ;
			my $Y_2 = $r->{'cmp_end'} ;

			push @{$hash_coords_equiv->{$R_chr}->{$A_chr}},"$X_1,$X_2=>$Y_1,$Y_2";
			push @{$hash_coords_equiv->{$A_chr}->{$R_chr}},"$Y_1,$Y_2=>$X_1,$X_2";

			# vertical 1st point
			my @pos =
			  map $_ / $sequence_scale, $ori == 1
			  ? (
				  $X_1,
				  0,
				  $X_1 ,
				  $Y_1 + $chr_offset,
			  )
			  : (
				  $X_2 ,
				  0,
				  $X_2 ,
				  $Y_1 + $chr_offset,
			  );
#			my $line = $canvas->createLine(
#							   @pos,
#							   -width => 1,
#							   -fill => $chr_offset ? 'lightPink' : 'lightGrey',
#							   -tags => [ 'ass_links', 'link' ],
#			);
#			$line = $top_canvas->createLine(
#							   @pos[0..2],$AXIS_WIDTH,
#							   -width => 1,
#							   -fill => $chr_offset ? 'lightPink' : 'lightGrey',
#							   -tags => [ 'ass_links', 'link' ],
#			);

			# horizontal 1st point
			@pos =
			  map $_ / $sequence_scale, $ori == 1
			  ? (
				  0,
				  $Y_1 + $chr_offset,
				  $X_1 ,
				  $Y_1 + $chr_offset,
			  )
			  : (
				  0,
				  $Y_1 + $chr_offset,
				  $X_2 ,
				  $Y_1 + $chr_offset,
			  );
#			$line = $canvas->createLine(
#										 @pos,
#										 -width => 1,
#										 -fill  => 'lightGrey',
#										 -tags  => [ 'ass_links', 'link' ],
#			);
#			$line = $left_canvas->createLine(
#											  @pos[0,1],$AXIS_WIDTH,$pos[3],
#											  -width => 1,
#											  -fill  => 'lightGrey',
#											  -tags  => [ 'ass_links', 'link' ],
#			);

			# vertical 2nd point
			@pos =
			  map $_ / $sequence_scale, $ori == 1
			  ? (
				  $X_2 ,
				  0,
				  $X_2 ,
				  $Y_2 + $chr_offset,
			  )
			  : (
				  $X_1 ,
				  0,
				  $X_1 ,
				  $Y_2 + $chr_offset,
			  );
#			$line = $canvas->createLine(
#							   @pos,
#							   -width => 1,
#							   -fill => $chr_offset ? 'lightPink' : 'lightGrey',
#							   -tags => [ 'ass_links', 'link' ],
#			);
#			$line = $top_canvas->createLine(
#							   @pos[0..2],$AXIS_WIDTH,
#							   -width => 1,
#							   -fill => $chr_offset ? 'lightPink' : 'lightGrey',
#							   -tags => [ 'ass_links', 'link' ],
#			);

			# horizontal 2nd point
			@pos =
			  map $_ / $sequence_scale, $ori == 1
			  ? (
				  0,
				  $Y_2  + $chr_offset,
				  $X_2 ,
				  $Y_2 + $chr_offset,
			  )
			  : (
				  0,
				  $Y_2 + $chr_offset,
				  $X_1 ,
				  $Y_2 + $chr_offset,
			  );
#			$line = $canvas->createLine(
#										 @pos,
#										 -width => 1,
#										 -fill  => 'lightGrey',
#										 -tags  => [ 'ass_links', 'link' ],
#			);
#			$line = $left_canvas->createLine(
#											  @pos[0,1],$AXIS_WIDTH,$pos[3],
#											  -width => 1,
#											  -fill  => 'lightGrey',
#											  -tags  => [ 'ass_links', 'link' ],
#			);
			$element_strings->[$i] = sprintf(
								 "%s:%s %d %d <=> %s:%s %d %d  ori %d",
								 $R_chr, $r_cs_version, $X_1,
								 $X_2, $A_chr, $a_cs_version,
								 $Y_1, $Y_2, $r->{'ori'}
			);

			# assembly mapping line
			@pos =
			  map $_ / $sequence_scale, $ori == 1
			  ? (
				  $X_1,
				  $Y_1 + $chr_offset,
				  $X_2, $Y_2 + $chr_offset,
			  )
			  : (
				  $X_2 ,
				  $Y_1 + $chr_offset,
				  $X_1, $Y_2 + $chr_offset,
			  );
			$canvas->createLine(
										 @pos,
										 -width => 2,
										 -fill  => 'black',
										 -tags  => [ 'alignment', $i ],
			);

			# draw the alignment shading here
			# a polygon on the central canvas
			@pos =  map $_ / $sequence_scale, (0,$Y_1 + $chr_offset,
											   $X_1,$Y_1 + $chr_offset,
											   $X_1,0,
											   $X_2,0,
											  $ori == 1 ? ($X_2,$Y_2 + $chr_offset) :
											  			  ($X_2,$Y_1 + $chr_offset, $X_1,$Y_2 + $chr_offset),
											   0,$Y_2 + $chr_offset);
#			$canvas->createPolygon(@pos,-width => 1,
#										 -fill  => 'linen',
#										 -outline => 'lightGrey',
#										 -tags  => [ 'shading', $i ]);
			# a rectangle on the left and top canvas
			@pos =  map $_ / $sequence_scale,(0,$Y_1 + $chr_offset,
											  $AXIS_WIDTH * $sequence_scale,$Y_2 + $chr_offset);
			$left_canvas->createRectangle(@pos,
										-width => 1,
										-fill => 'linen',
										-outline => 'lightGrey',
										-tags => ["shading", $i]);
			@pos =  map $_ / $sequence_scale,($X_1,0,
											  $X_2 ,$AXIS_WIDTH * $sequence_scale);
			$top_canvas->createRectangle(@pos,
										-width => 1,
										-fill => 'linen',
										-outline => 'lightGrey',
										-tags => ["shading", $i]);


			$i++;
		}
		$chr_offset += $alt_length;
	}



	foreach my $R_seg (@R_components) {
		my $R_component = $R_seg->to_Slice;
		my $sr_name     = $R_component->seq_region_name;
		my $sr_start    = $R_component->start;
		my $sr_end      = $R_component->end;
		my $strand      = $R_component->strand;
		my $chr_start   = $R_seg->from_start;
		my $chr_end     = $R_seg->from_end;
		my $color       = $i % 2 ? 'black' : 'red';
		$element_strings->[$i] =
		  $R_chr . " " . join( ":", $sr_name, $strand, $chr_start, $chr_end );
		my @pos = map $_ / $sequence_scale,
		  (
			$chr_start - 1,
			$axis_offset * $sequence_scale,
			$chr_end, $axis_offset * $sequence_scale,
		  );
		my $position = $strand == -1 ? 'first' : 'last';
		$top_canvas->createLine(
											@pos,
											-width => 1,
											-fill  => $color,
											-tags  => [ 'ref_contig', $i ],
											-arrow => $position
		);
		$i++;
	}

	$left_canvas->lower('shading','scale');
	$top_canvas->lower('shading','scale');
	$canvas->lower('shading','scale');



	## Start the command bindings here

	# Highlight the alignment
	$canvas->bind( 'alignment', '<Button-1>',
				   [ \&show_align_match, \$align_txt, $canvas, $top_canvas,$left_canvas ] );
	$canvas->bind( 'shading', '<Button-1>',
				   [ \&show_align_match, \$align_txt, $canvas, $top_canvas,$left_canvas ] );
	$top_canvas->bind( 'shading', '<Button-1>',
				   [ \&show_align_match, \$align_txt, $canvas,$top_canvas,$left_canvas ] );
	$left_canvas->bind( 'shading', '<Button-1>',
				   [ \&show_align_match, \$align_txt, $canvas,$top_canvas,$left_canvas ] );

	# Highlight the clicked objects (contigs, transcripts) on the x/y axis
	$top_canvas->bind( 'ref_contig', '<Button-1>',
					   [ \&show_axis_match, \$ref_txt ] );
	$top_canvas->bind( 'transcript', '<Button-1>',
					   [ \&show_axis_match, \$ref_txt ] );
	$left_canvas->bind( 'alt_contig', '<Button-1>',
						[ \&show_axis_match, \$alt_txt ] );
	$left_canvas->bind( 'transcript', '<Button-1>',
						[ \&show_axis_match, \$alt_txt ] );

	# Highlight transcript in listbox and zoom in the transcript area
	$gene_lb->bind('<<ListboxSelect>>' => [\&show_transcript,$canvas,$top_canvas,$left_canvas,\$alt_txt,\$ref_txt,\@box,\@top_box,\@left_box]);

	$canvas->CanvasBind(
		'<ButtonPress-1>' => [\&print_coords,Ev('x'), Ev('y') ]	);

	# Red rectanlgle Zoom
	my $zoomRect;
	my @zoomRectCoords;
	$canvas->CanvasBind(
		'<ButtonPress-3>' => sub {
			my $x = $canvas->canvasx( $Tk::event->x );
			my $y = $canvas->canvasy( $Tk::event->y );
			@zoomRectCoords = ( $x, $y, $x, $y );
			$zoomRect =
			  $canvas->createRectangle( @zoomRectCoords, -outline => 'red', );
		}
	);
	$canvas->CanvasBind(
		'<B3-Motion>' => sub {
			@zoomRectCoords[ 2, 3 ] = (
										$canvas->canvasx( $Tk::event->x ),
										$canvas->canvasy( $Tk::event->y )
			);
			$canvas->coords( $zoomRect => @zoomRectCoords );
		}
	);
	$canvas->CanvasBind(
		'<ButtonRelease-3>' => sub {

			# Delete the rectangle.
			$canvas->delete($zoomRect);


			return
			  if abs( $zoomRectCoords[0] - $zoomRectCoords[2] ) < 10
			  || abs( $zoomRectCoords[1] - $zoomRectCoords[3] ) < 10;

			my ($X1,$Y1,$X2,$Y2) = @zoomRectCoords;

			($X1,$X2) = ($X2,$X1) unless $X1 < $X2;
			($Y1,$Y2) = ($Y2,$Y1) unless $Y1 < $Y2;

			&zoom_region($canvas,$top_canvas,$left_canvas,$X1,$Y1,$X2,$Y2,,\@box,\@top_box,\@left_box);

		}
	);

	# Canvas drag
	$canvas->CanvasBind( '<2>'         => [ scanMark   => Ev('x'), Ev('y') ] );
	$canvas->CanvasBind( '<B2-Motion>' => [ scanDragto => Ev('x'), Ev('y') ] );

	# Zoom in X2
	$canvas->Tk::bind(ref $canvas, '<Button-4>','');
	$canvas->CanvasBind(
		'<Button-4>' => [\&zoom,$top_canvas,$left_canvas,2,Ev('x'), Ev('y'),undef,undef,\@box,\@top_box,\@left_box ]
	);
	# Zoom out X1/2
	$canvas->Tk::bind(ref $canvas, '<Button-5>','');
	$canvas->CanvasBind(
		'<Button-5>' => [\&zoom,$top_canvas,$left_canvas,0.5,Ev('x'), Ev('y'),undef,undef,\@box,\@top_box,\@left_box ]
	);

	Tk::MainLoop();
}

sub zoom_region {
	my ($canvas,$top,$left,$X1,$Y1,$X2,$Y2,$b,$t_b,$l_b) = @_;

	my $dx = $canvas->width / ($X2 - $X1);
	my $dy = $canvas->height / ($Y2 -$Y1);

	my $zoom_factor = [ $dx => $dy ]->[ $dy <= $dx ];


	&zoom($canvas,$top,$left,$zoom_factor,undef,undef,$X1,$Y1,$b,$t_b,$l_b);
}

sub zoom {
	my ($canvas,$top,$left,$zoom_factor,$ev_x,$ev_y,$x,$y,$b,$t_b,$l_b) = @_;

	$x = defined $ev_x ? $canvas->canvasx($ev_x) : $x;
	$y = defined $ev_y ? $canvas->canvasy($ev_y) : $y;
	$ev_x ||= 0;
	$ev_y ||= 0;

	if ( $zoom_factor * $zoom_scale < 1 ) {
		$zoom_factor = 1 / $zoom_scale;
	} elsif ($zoom_factor * $zoom_scale > 200000 ) {
				$zoom_factor = 200000 / $zoom_scale;
	}

	$zoom_scale *= $zoom_factor;

	$canvas->scale( 'all' => 0, 0, $zoom_factor, $zoom_factor );
	$top->scale( 'all' => 0, 0, $zoom_factor, 1 );
	$left->scale( 'all' => 0, 0, 1, $zoom_factor );
	$_ *= $zoom_factor for @$b;
	$_ *= $zoom_factor for @$t_b[ 0, 2 ];
	$_ *= $zoom_factor for @$l_b[ 1, 3 ];
	$canvas->configure( -scrollregion      => $b );
	$top->configure( -scrollregion  => $t_b );
	$left->configure( -scrollregion => $l_b );


	my $Y =  $y * $zoom_factor;
	my $X =  $x * $zoom_factor;
	my $x_fraction =  ($X - $ev_x) / @$b[2];
	my $y_fraction =  ($Y - $ev_y) / @$b[3];

	$canvas->xviewMoveto( $x_fraction );
	$canvas->yviewMoveto( $y_fraction );
}

sub get_equiv_coords {
	my ($from,$from_start,$from_end) = @_;

	my ($s_s, $s_e, $slength);
	my $from_length = $hash_coords_equiv->{$from}->{'length'};
	foreach(keys %{$hash_coords_equiv->{$from}}){
		my $array = $hash_coords_equiv->{$from}->{$_};
		next unless ref $array eq 'ARRAY';
		my $to_length = $hash_coords_equiv->{$_}->{'length'};
		my ($to_start,$to_end);
		my ( $start_idx, $end_idx, $mid_idx );

	    $start_idx = 0;
	    $end_idx = $#$array;
	    my ($f_start,$f_end,$t_start,$t_end) ;

	   # binary search the relevant pairs
	   # helps if the list is big
	   while(( $end_idx - $start_idx ) > 1 ) {
	     $mid_idx = ($start_idx+$end_idx)>>1;
	     ($f_start)   = $array->[$mid_idx] =~ /^(\d+)\,\d+=>.*/;
	     if( $f_start < $from_start ) {
	       $start_idx = $mid_idx;
	     } else {
	       $end_idx = $mid_idx;
	     }
	   }

	   my $i = $start_idx;

	   $start_idx = 0;
	   $end_idx = $#$array;

	   while(( $end_idx - $start_idx ) > 1 ) {
	     $mid_idx = ($start_idx+$end_idx)>>1;
	     ($f_end)   = $array->[$mid_idx] =~ /^\d+\,(\d+)=>.*/;
	     if( $from_end > $f_end ) {
	       $start_idx = $mid_idx;
	     } else {
	       $end_idx = $mid_idx;
	     }
	   }

		my ($start_flag,$end_flag);

	   for(; $i<=$end_idx; $i++ ) {
	     	($f_start,$f_end,$t_start,$t_end)   = $array->[$i] =~ /^(\d+)\,(\d+)=>(\d+)\,(\d+)$/;
			# from_start outside align block
			if( $f_end < $from_start && !$start_flag) {
				$to_start = $t_end;
				$start_flag = 1;
			}
			# from_start within align block
			if( $f_start <= $from_start && $from_start <= $f_end ){
				$to_start = $t_start + ($from_start - $f_start);
	     	}
	     	# from_end outside align block
	     	if($from_end < $f_start && !$end_flag){
				$to_end = $t_start;
	     	}
	     	# from_end within align block
	     	if( $f_start <= $from_end && $from_end <= $f_end ){
				$to_end = $t_start + ($from_end - $f_start);
				$end_flag = 1;
	     	}
	   }

		$to_start ||= 0;
		$to_end ||= $to_length;

		if(!defined($slength) || ( defined($slength) && $slength > ($to_end - $to_start))) {
			($s_s, $s_e) = ($to_start,$to_end);
		}
		$slength = $to_end - $to_start;
	}

	return ($s_s, $s_e);
}



sub print_coords {
	my ($c,$x,$y) = @_;
	my $X = $c->canvasx($x) ;
	my $Y = $c->canvasy($y) ;
	print STDOUT "<ButtonPress-1> ($x,$y) canvaX/Y ($X,$Y)\n";
}

my %current_gene_sid;
sub get_gene_objects {
	my ($dba,$entry1,$query_f,$gene_lb,$R_chr,$A_chr) = @_;
	my $query_str = ${$entry1->cget(-textvariable)};
	return unless $query_str;
	$query_str =~ s/^\s+|\s+$//g; # trim leading/trailing spaces
	my $found_gsids = [];
	foreach my $q (split /,/,$query_str) {
		push @$found_gsids, @{process_query($q, $dba, $query_f,0,1)};
	}
	my $ga = $dba->get_GeneAdaptor;

	GSI:foreach(@$found_gsids) {
		my $gene = $ga->fetch_by_stable_id($_);
		next GSI unless $gene;
		my $seq_region_name = $gene->seq_region_name;
		if($seq_region_name !~ /$R_chr|$A_chr/) {
			print STDERR "$_ found on $seq_region_name\n";
			next GSI;
		}
		next GSI if $current_gene_sid{$_};

		my $gene_color = $colors[$c++];
		$c = 0 unless $c < scalar @colors;
		$gene_lb->insert(0, $seq_region_name.":".$_);
		foreach my $t (@{$gene->get_all_Transcripts}) {
			$gene_lb->insert(1, "    -".$t->stable_id);
			&draw_transcript($t,$seq_region_name,$gene_color);
			$current_gene_sid{$_}->{$t->stable_id} = $t;
		}
	}
}

sub draw_transcript {
	my ($transcript, $seq_region_name, $gene_color) = @_;
	my ($c,$offset) = &chr2canvas($seq_region_name);
	my $c_height = $c->cget('height');
	my $c_width  = $c->cget('width');
	my $strand   = $transcript->strand;
	my ($bot,$mid,$top) =
			$strand * ( $c_height > $c_width == 1 ? -1 : 1) == 1 ?
				(0,$AXIS_WIDTH/3,$AXIS_WIDTH/2):
				($AXIS_WIDTH/2,3*$AXIS_WIDTH/4,$AXIS_WIDTH);

	my ($exon_start,$exon_end,$exon_last_end,$exon_mid);

	$element_strings->[$i] = join(":",
								  map(
								  	$transcript->${_},
									('seq_region_name','stable_id','start','end','strand','biotype')
								  )
	);

	foreach my $exon (sort {$a->start <=> $b->start } @{$transcript->get_all_Exons}) {
		$exon_start = $exon->start / $sequence_scale * $zoom_scale;
		$exon_end   = $exon->end / $sequence_scale * $zoom_scale;
		$exon_mid = $exon_last_end ?
			($exon_end - $exon_last_end) / 2 + $exon_last_end : 0;
		my ($coords,$line_1,$line_2);
		if($c_height > $c_width) { # 1 => left canvas, 0 => top canvas
			$coords = [$bot,$exon_start,$top,$exon_end];
			$line_1 = [$mid, $exon_last_end, $strand == 1 ? $top : $bot, $exon_mid];
			$line_2 = [$strand == 1 ? $top : $bot, $exon_mid, $mid, $exon_start];
		} else {
			$coords = [$exon_start,$bot,$exon_end,$top];
			$line_1 = [$exon_last_end, $mid, $exon_mid, $strand == -1 ? $top : $bot ];
			$line_2 = [$exon_mid, $strand == -1 ? $top : $bot, $exon_start, $mid];
		}

		# draw the joining line between two exons
		if($exon_last_end){
			$c->createLine(@$line_1,-width => 1, -fill => $gene_color,-tags => ["transcript", $i,$transcript->stable_id]);
			$c->createLine(@$line_2,-width => 1, -fill => $gene_color,-tags => ["transcript", $i,$transcript->stable_id]);
		}
		# draw the exon
		$c->createRectangle(@$coords,-width => 1, -fill => $gene_color,-tags => ["transcript", $i,$transcript->stable_id]);
		$exon_last_end = $exon_end;
	}
	$i++;
}

sub show_transcript {
	my ( $lb,$canvas,$top,$left,$alt_text,$ref_text,$b,$t_b,$l_b ) = @_;
	foreach my $i ($lb->curselection()){
		my $item = $lb->get($i);
		if($item =~ /^    -(.*)$/){
			my $ttag = $1;
			my ($c,$start,$end);
			foreach $c ($top,$left) {
				my $t = $c->find('withtag',"transcript&&$ttag");
				next unless $t;
				my ($match) = grep /^\d+$/, $c->gettags(shift @$t);
				my $text = $c eq $top ? $ref_text : $alt_text;
				${$text} = $element_strings->[$match];
				my @array = split(/:/,$element_strings->[$match]);
				my ($seq_region,$start,$end) = @array[0,2,3];
				my ($equiv_start,$equiv_end) = &get_equiv_coords($seq_region,$start,$end);
				&outline_match($c,$t);
				$start -= ($end-$start) * 1/3;
				$end   += ($end-$start) * 1/3;
				my @coords = $c eq $top ? ($start,$equiv_start,$end,$equiv_end):
										  ($equiv_start,$start,$equiv_end,$end);
				@coords = map ($_ / $sequence_scale * $zoom_scale , @coords );
				&zoom_region($canvas,$top,$left,@coords,$b,$t_b,$l_b);

				last;
			}
		}
	}
}

my $chr2c_hash = {};
sub chr2canvas {
	my ($chr,$c,$offset) = @_;
	if($chr && $c) {
		$chr2c_hash->{$chr} = [$c,$offset];
	}

	return @{$chr2c_hash->{$chr}};
}

sub show_axis_match {
	my ( $canvas, $text ) = @_;
	my $item = $canvas->find( 'withtag', 'current' );
	my ($match) = grep /^\d+$/, $canvas->gettags($item);
	outline_match( $canvas, $item );
	${$text} = $element_strings->[$match];
}

sub show_align_match {
	my ( $canvas, $text, $center, $top, $left ) = @_;
	my $item = $canvas->find( 'withtag', 'current' );
	my ($match) = grep /^\d+$/, $canvas->gettags($item);

	foreach my $c ($center, $top, $left) {
		$c->delete('shading_outline');
		foreach my $i ($c->find(  'withtag',"shading&&$match")) {
			my $method = $c->type($i) eq 'polygon' ?
				 'createPolygon' : 'createRectangle';
			my $shad = $c->$method(
					   $c->coords($i),
					   -width     => 1,
					   -outline => 'lightGrey',
					   -fill      => 'LemonChiffon',
					   -tags      => ['shading_outline']);
			$c->lower('shading_outline','scale');
		}
		foreach my $i ($c->find(  'withtag',"alignment&&$match")) {
			my ($x1,$y1,$x2,$y2) = $c->coords($i);
			my @coords = $x1 < $x2 ?
					(0,$y1,$x1,$y1,$x1,0,$x2,0, $x2,$y2,0,$y2):
					(0,$y1,$x2,$y1,$x2,0,$x1,0, $x1,$y1,$x2,$y2,0,$y2);
			$c->createPolygon(
					   @coords,
					   -width     => 1,
					   -outline => 'lightGrey',
					   -fill      => 'LemonChiffon',
					   -tags      => ['shading_outline']);
			$c->lower('shading_outline','scale');

		}
	}

	outline_match( $center, [$center->find(  'withtag',"alignment&&$match")] );
	${$text} = $element_strings->[$match];
}



sub outline_match {
	my ( $canvas, $items ) = @_;
	$canvas->delete('match_outline');
	my @tags = $canvas->gettags(shift @$items);
	# remove current tag
	pop @tags if ($tags[-1] && $tags[-1] eq 'current');
	foreach my $item ($canvas->find('withtag', join("&&",@tags))) {
		if($canvas->type($item) eq 'line') {
			$canvas->createLine(
									   $canvas->coords($item),
									   -width     => 3,
									   -fill      => 'gold',
									   -joinstyle => 'round',
									   -tags      => ['match_outline']);

		}else{
			$canvas->createRectangle(
									   $canvas->coords($item),
									   -width     => 1,
									   -fill      => 'gold',
									   -tags      => ['match_outline']);
		}
	}
}

sub get_canvas_window {
	my ($mw) = @_;
	my $frame = $mw->Frame()->pack;
	$mw->{_left_frame} =
	  $frame->Frame()->pack( -side => 'left', -fill => 'y', -expand => 1 );
	$mw->{_top_frame} =
	  $frame->Frame()->pack( -side => 'top', -fill => 'x', -expand => 1 );
	$mw->{_central_frame} =
	  $frame->Frame()->pack( -side => 'top', -fill => 'both', -expand => 1 );

	# CENTRAL CANVAS
	$mw->{_central_canvas} = $mw->{_central_frame}->Canvas(   -height => $C_HEIGHT,
														   -width  => $C_WIDTH );
	$mw->{_central_canvas}->pack( -side => 'top', -expand => 1 );

	# TOP CANVAS
	my $xsb =
	  $mw->{_top_frame}->Scrollbar( -orient => 'horizontal' )
	  ->pack( -side => 'top', -fill => 'x', -expand => 1 );
	$mw->{_top_canvas} = $mw->{_top_frame}->Canvas(
													-height => $AXIS_WIDTH,
													-width  => $C_WIDTH
	)->pack( -side => 'top', -fill => 'both', -expand => 1 );

	# LEFT CANVAS
	my $ysb           = $mw->{_left_frame}->Scrollbar( -orient => 'vertical', );
	my $size          = $ysb->cget('-width') + 2 * $ysb->cget('-borderwidth');
	my $corner_height =
	  $AXIS_WIDTH + $xsb->cget('-width') + 2 * $xsb->cget('-borderwidth');
	my $corner_width =
	  $AXIS_WIDTH + $ysb->cget('-width') + 2 * $ysb->cget('-borderwidth');
	my $canvas_corner = Tk::Frame->new(
										$mw->{_left_frame},
										Name        => 'canvas_corner',
										-width      => $corner_width,
										-height     => $corner_height,
										-background => 'brown',
										-relief => 'sunken'
	);

	$mw->{_left_canvas} = $mw->{_left_frame}->Canvas(    -height => $C_HEIGHT,
													  -width  => $AXIS_WIDTH );
	$canvas_corner->pack( -side => 'top', -expand => 1 );
	$mw->{_left_canvas}
	  ->pack( -side => 'right', -fill => 'both', -expand => 1 );
	$ysb->pack( -side => 'left', -fill => 'both', -expand => 1 );

	# COMMAND CONFIGURATION
	my $canvas_list =
	  [ $mw->{_left_canvas}, $mw->{_top_canvas}, $mw->{_central_canvas} ];
	foreach my $c ( $mw->{_central_canvas} ) {
		$c->configure(
			  -xscrollcommand => [ \&scroll_canvas, $xsb, $c, $canvas_list, 1 ],
			  -yscrollcommand => [ \&scroll_canvas, $ysb, $c, $canvas_list, 0 ] );
	}
	$xsb->configure(
		-command => sub {
			foreach my $c (@$canvas_list) {
				$c->xview(@_);
			}
		}
	);
	$ysb->configure(
		-command => sub {
			foreach my $c (@$canvas_list) {
				$c->yview(@_);
			}
		}
	);

	return $mw;
}

sub scroll_canvas {
	my ( $sb, $c, $canvas, $is_x, @args ) = @_;
	$sb->set(@args);    # tell the Scrollbar what to display
	my ( $top, $bottom ) = $is_x ? $c->xview() : $c->yview();
	foreach $c (@$canvas) {
		$is_x
		  ? $c->xviewMoveto($top)
		  : $c->yviewMoveto($top);    # adjust each canvas
	}
}

sub get_db_param {
	my ($dbhost) = @_;
	my ( $dbuser, $dbpass, $dbport );
	my $ref = Net::Netrc->lookup($dbhost);
	throw("$dbhost entry is missing from ~/.netrc") unless ($ref);
	$dbuser = $ref->login;
	$dbpass = $ref->password;
	$dbport = $ref->account;
	throw(
		"Missing parameter in the ~/.netrc file:\n
			machine " .  ( $dbhost || 'missing' ) . "\n
			login " .    ( $dbuser || 'missing' ) . "\n
			password " . ( $dbpass || 'missing' ) . "\n
			account "
		  . ( $dbport || 'missing' )
		  . " (should be used to set the port number)"
	  )
	  unless ( $dbuser && $dbpass && $dbport );
	return ( $dbuser, $dbpass, $dbport );
}

package Bio::Otter::Utils::Script::Transcript;

use namespace::autoclean;

use Moose;

has 'transcript_id' => ( is => 'ro', isa => 'Int', required => 1 );
has 'stable_id'     => ( is => 'ro', isa => 'Str' );
has 'name'          => ( is => 'ro', isa => 'Str' );

# Sort this out properly later
# has 'gene' => (
#     is       => 'ro',
#     isa      => 'Bio::Otter::Utils::Script::Gene',
#     weak_ref => 1,
#     );

has 'gene_id'        => ( is => 'ro', isa => 'Int' );
has 'gene_stable_id' => ( is => 'ro', isa => 'Str' );
has 'gene_name'      => ( is => 'ro', isa => 'Str' );

# has 'seq_region' => (
#     is       => 'ro',
#     isa      => 'Bio::Otter::Utils::Script::SeqRegion',
#     weak_ref => 1,
#     );

has 'seq_region_name'   => ( is => 'ro', isa => 'Str' );
has 'seq_region_hidden' => ( is => 'ro', isa => 'Bool' );

has 'dataset' => (
    is       => 'ro',
    isa      => 'Bio::Otter::Utils::Script::DataSet',
    weak_ref => 1,
    handles  => [ qw( script ) ],
    );

around BUILDARGS => sub {
    my ($orig ,$class, %args) = @_;

    $args{stable_id} = delete $args{transcript_stable_id};
    $args{name}      = delete $args{transcript_name};

    # This is hokey as we need a dataset list of genes
    # if (my $gene_id = delete $args{gene_id}) {
    #     my %gene_spec = (
    #         gene_id   => $gene_id,
    #         stable_id => delete $args{gene_stable_id),
    #         name      => delete $args{gene_name),
    #         );
    #     $args{gene} = Bio::Otter::Utils::Script::Gene->new(%gene_spec);
    # }

    return $class->$orig(%args);
};

__PACKAGE__->meta->make_immutable;

1;

# EOF

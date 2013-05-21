all: test.clone.full test.clone.vulgar test.ts.full test.ts.vulgar test.ts.rev.vulgar
all: test.exons.fwd.full test.exons.fwd.vulgar test.exons.rev.full test.exons.rev.vulgar
all: protein.clone.full protein.clone.vulgar protein.ts.full protein.ts.vulgar
all: Q5SV42.full

INTERMEDIATES  = random.fa insert.fa region.insert.fa region.indel.fa region.indel.rev.fa tmp_clone.fa
INTERMEDIATES += BC018923.rev.fa BC018923.rev.int.fa BC018923.fwd.fa

clean:
	rm $(INTERMEDIATES)

## Create test clone by inserting fwd & rev copies of the region of interest into a random sequence.
#
random.fa:
	makenucseq -auto -amount 1 -length 100000 -outseq $@ -osdbname 'TestSeq'

# Make an insertion into exon 2
insert.fa:
	newseq -auto -name 'Insert' -sequence 'T' -outseq $@

region.insert.fa: region.fa insert.fa
	pasteseq region.fa insert.fa -pos 13310 -outseq $@

# Make a deletion from exon 4 - 14838
region.indel.fa: region.insert.fa
	cutseq $< -from 14838 -to 14839 -outseq $@

# Make a reversed copy of the manipulated region
region.indel.rev.fa: region.indel.fa
	revseq $< $@

# Insert fwd & rev regions
tmp_clone.fa: region.indel.fa random.fa
	pasteseq random.fa region.indel.fa -pos 70000 -outseq $@

test_clone.fa: region.indel.rev.fa tmp_clone.fa
	pasteseq -supper tmp_clone.fa region.indel.rev.fa -pos 25000 -outseq $@

## Create test queries
#
BC018923.rev.int.fa: BC018923.fasta
	revseq $< $@

BC018923.rev.fa: BC018923.rev.int.fa
	descseq -seq $< -out $@ -name 'BC018923.rev'

BC018923.fwd.fa: BC018923.fasta
	descseq -seq $< -out $@ -name 'BC018923.fwd'

test_query.fa: BC018923.fwd.fa BC018923.rev.fa
	cat $^ > $@

FWD_EXONS = e_fwd.1.fa e_fwd.2.fa e_fwd.3.fa e_fwd.4.fa e_fwd.5.fa e_fwd.6.fa e_fwd.7.fa
test_ts.fa $(FWD_EXONS): test_clone.fa BC018923.fwd.fa exons.fwd.txt
	./extract_exons.pl --clone test_clone.fa --query BC018923.fwd.fa --transcript test_ts.fa \
                           --spec exons.fwd.txt --exon_base e_fwd

REV_EXONS = e_rev.1.fa e_rev.2.fa e_rev.3.fa e_rev.4.fa e_rev.5.fa e_rev.6.fa e_rev.7.fa
test_ts.rev.fa $(REV_EXONS): test_clone.fa BC018923.rev.fa exons.rev.txt
	./extract_exons.pl --clone test_clone.fa --query BC018923.rev.fa --transcript test_ts.rev.fa \
                           --spec exons.rev.txt --exon_base e_rev

exons.fwd.fa:	$(FWD_EXONS)
	cat $(FWD_EXONS) > $@

exons.rev.fa:	$(REV_EXONS)
	cat $(REV_EXONS) > $@

## Exonerate to get results
#
EXONERATE_PARAMS  = --bestn 1 -M 500 --maxintron 200000 --score 100
EXONERATE_PARAMS += --showvulgar true --showcigar true

EXONERATE_DNA_PARAMS = $(EXONERATE_PARAMS)
EXONERATE_DNA_PARAMS += --model est2genome
EXONERATE_DNA_PARAMS += --dnahspthreshold 120 --geneseed 300

EXONERATE_PROTEIN_CLONE_PARAMS = $(EXONERATE_PARAMS) --model protein2genome
EXONERATE_PROTEIN_TS_PARAMS    = $(EXONERATE_PARAMS) --model protein2dna:bestfit --exhaustive

EXONERATE_CLONE_DNA_SEQS = --target test_clone.fa --query test_query.fa
EXONERATE_TS_DNA_SEQS    = --target test_ts.fa    --query test_query.fa

EXONERATE_FWD_EXON_SEQS = --target test_clone.fa --query exons.fwd.fa
EXONERATE_REV_EXON_SEQS = --target test_clone.fa --query exons.rev.fa

EXONERATE_CLONE_PROTEIN_SEQS = --target test_clone.fa --query Q96S55.fasta
EXONERATE_TS_PROTEIN_SEQS    = --target test_ts.fa    --query Q96S55.fasta

test.clone.full: test_clone.fa test_query.fa
	exonerate $(EXONERATE_CLONE_DNA_SEQS) $(EXONERATE_DNA_PARAMS) > $@

test.clone.vulgar: test_clone.fa test_query.fa
	exonerate $(EXONERATE_CLONE_DNA_SEQS) $(EXONERATE_DNA_PARAMS) --showalignment false > $@

test.ts.full:	test_ts.fa test_query.fa
	exonerate $(EXONERATE_TS_DNA_SEQS) $(EXONERATE_DNA_PARAMS) > $@

test.ts.vulgar: test_ts.fa test_query.fa
	exonerate $(EXONERATE_TS_DNA_SEQS) $(EXONERATE_DNA_PARAMS) --showalignment false > $@

test.ts.rev.vulgar: test.ts.vulgar reverse.pl
	perl -I ~/Work/git/ensembl-otter/modules ./reverse.pl test.ts.vulgar > $@

test.exons.fwd.full: test_clone.fa exons.fwd.fa
	exonerate $(EXONERATE_FWD_EXON_SEQS) $(EXONERATE_DNA_PARAMS) > $@

test.exons.fwd.vulgar: test_clone.fa exons.fwd.fa
	exonerate $(EXONERATE_FWD_EXON_SEQS) $(EXONERATE_DNA_PARAMS) --showalignment false > $@

test.exons.rev.full: test_clone.fa exons.rev.fa
	exonerate $(EXONERATE_REV_EXON_SEQS) $(EXONERATE_DNA_PARAMS) > $@

test.exons.rev.vulgar: test_clone.fa exons.rev.fa
	exonerate $(EXONERATE_REV_EXON_SEQS) $(EXONERATE_DNA_PARAMS) --showalignment false > $@

protein.clone.full: test_clone.fa Q96S55.fasta
	exonerate $(EXONERATE_CLONE_PROTEIN_SEQS) $(EXONERATE_PROTEIN_CLONE_PARAMS) > $@

protein.clone.vulgar: test_clone.fa Q96S55.fasta
	exonerate $(EXONERATE_CLONE_PROTEIN_SEQS) $(EXONERATE_PROTEIN_CLONE_PARAMS) --showalignment false > $@

protein.ts.full:	test_ts.fa Q96S55.fasta
	exonerate $(EXONERATE_TS_PROTEIN_SEQS) $(EXONERATE_PROTEIN_TS_PARAMS) > $@

protein.ts.vulgar: test_ts.fa Q96S55.fasta
	exonerate $(EXONERATE_TS_PROTEIN_SEQS) $(EXONERATE_PROTEIN_TS_PARAMS) --showalignment false > $@

Q5SV42.full: Q5SV42.fasta AL139092.12.fasta
	exonerate --target AL139092.12.fasta --query Q5SV42.fasta $(EXONERATE_PROTEIN_CLONE_PARAMS) > $@

# EOF

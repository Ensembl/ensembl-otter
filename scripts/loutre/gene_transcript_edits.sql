
-- New trancripts in exisiting genes
SELECT sr.name
  , count(*) transcripts
FROM transcript t
  , gene g
  , transcript_stable_id tsid
  , gene_stable_id gsid
  , seq_region sr
  , seq_region_attrib sra
  , attrib_type at
  , coord_system cs
WHERE g.gene_id = t.gene_id
  AND t.transcript_id = tsid.transcript_id
  AND g.gene_id = gsid.gene_id
  AND g.seq_region_id = sr.seq_region_id
  AND sr.seq_region_id = sra.seq_region_id
  AND sra.attrib_type_id = at.attrib_type_id
  AND sr.coord_system_id = cs.coord_system_id
  AND cs.name = 'chromosome'
  AND cs.version = 'Otter'
  AND at.code = 'hidden'
  AND sra.value = 0
  AND g.is_current = 1
  AND g.source = 'havana'
  AND tsid.created_date BETWEEN '2007-10-01' AND '2008-01-01'
  AND gsid.created_date < '2007-10-01'
GROUP BY sr.name

    name       transcripts
    --------   -----------
    chr1-11              2
    chr2-03            157
    chr3-02              8
    chr5-02              6
    chr6-16              4
    chr7-03             74
    chr9-17              1
    chr10-09             2
    chr11-02             9
    chr13-12             1
    chr15-02             8
    chr16-02            14
    chr17-02             2
    chr20-11             2
    chr21-03             2
    chr22-07           205
    chrX-09              8


SELECT sr.name chr
  , g.biotype
  , count(*) genes
FROM gene g
  , gene_stable_id gsid
  , seq_region sr
WHERE g.gene_id = gsid.gene_id
  AND g.seq_region_id = sr.seq_region_id
  AND sr.name IN ('chr2-03', 'chr7-03')
  AND g.is_current = 1
  AND g.source = 'havana'
  AND gsid.created_date BETWEEN '2007-10-01' AND '2008-01-01'
GROUP BY sr.name, g.biotype

    chr      biotype                 genes
    -------  ----------------------  -----
    chr2-03  artifact                    4
    chr2-03  novel_transcript           32
    chr2-03  polymorphic                 1
    chr2-03  processed_pseudogene        4
    chr2-03  processed_transcript       36
    chr2-03  protein_coding             20
    chr2-03  unprocessed_pseudogene      3
    chr7-03  artifact                    3
    chr7-03  novel_transcript           26
    chr7-03  processed_pseudogene       10
    chr7-03  processed_transcript       18
    chr7-03  protein_coding             35
    chr7-03  unprocessed_pseudogene      4

--AND cs.version = 'Otter'

SELECT sr.name chr
  , t.biotype
  , count(*) transcripts
FROM transcript t
  , gene g
  , transcript_stable_id tsid
  , seq_region sr
WHERE g.gene_id = t.gene_id
  AND t.transcript_id = tsid.transcript_id
  AND t.seq_region_id = sr.seq_region_id
  AND sr.name IN ('chr2-03', 'chr7-03')
  AND g.is_current = 1
  AND g.source = 'havana'
  AND tsid.created_date BETWEEN '2007-10-01' AND '2008-01-01'
GROUP BY sr.name, t.biotype

    chr      biotype                  transcripts
    -------  -----------------------  -----------
    chr2-03  artifact                          29
    chr2-03  nonsense_mediated_decay           33
    chr2-03  processed_pseudogene               4
    chr2-03  processed_transcript             175
    chr2-03  protein_coding                   126
    chr2-03  retained_intron                   70
    chr2-03  unprocessed_pseudogene             4
    chr7-03  artifact                           9
    chr7-03  nonsense_mediated_decay           18
    chr7-03  processed_pseudogene              10
    chr7-03  processed_transcript             120
    chr7-03  protein_coding                   143
    chr7-03  retained_intron                   51
    chr7-03  unprocessed_pseudogene             4

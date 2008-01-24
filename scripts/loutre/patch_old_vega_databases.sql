
update transcript
   set biotype = lcase(biotype);

update transcript 
   set biotype = 'protein_coding' 
 where biotype = 'coding';

update transcript 
   set biotype = 'processed_transcript' 
 where biotype = 'transcript';

UPDATE transcript 
   SET biotype = 'processed_transcript',
       status  = 'PUTATIVE'
 WHERE biotype = 'putative'
   AND status  = 'UNKNOWN';

UPDATE transcript
   SET biotype = 'transcribed_pseudogene'
 WHERE biotype = 'expressed_pseudogene';

UPDATE gene
   SET biotype = 'transcribed_pseudogene'
 WHERE biotype = 'expressed_pseudogene';

UPDATE transcript
   SET biotype = 'protein_coding',
	   status  = 'KNOWN'
 WHERE biotype = 'known_cds';

UPDATE transcript
   SET biotype = 'protein_coding',
	   status  = 'PUTATIVE'
 WHERE biotype = 'putative_cds';

UPDATE transcript
   SET biotype = 'protein_coding',
	   status  = 'NOVEL'
 WHERE biotype = 'novel_cds';

UPDATE gene
   SET biotype = lcase(biotype)
 WHERE biotype like 'Ig%';

update gene 
   set status = 'NOVEL'
 where status = 'UNKNOWN';

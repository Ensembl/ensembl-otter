

    UPDATE gene
    SET biotype = 'protein_coding'
      , status = 'KNOWN'
    WHERE biotype = 'known'
      AND status = 'KNOWN';

    UPDATE gene
    SET biotype = 'protein_coding'
      , status = 'KNOWN'
    WHERE biotype = 'known'
      AND status = 'UNKNOWN';

    UPDATE gene
    SET biotype = 'processed_transcript'
      , status = 'NOVEL'
    WHERE biotype = 'novel_transcript'
      AND status = 'UNKNOWN';

    UPDATE gene
    SET biotype = 'processed_transcript'
      , status = 'KNOWN'
    WHERE biotype = 'novel_transcript'
      AND status = 'KNOWN';

    UPDATE gene
    SET biotype = 'processed_transcript'
      , status = 'PUTATIVE'
    WHERE biotype = 'putative'
      AND status = 'UNKNOWN';

    UPDATE gene
    SET biotype = 'processed_transcript'
      , status = 'PUTATIVE'
    WHERE biotype = 'putative'
      AND status = 'KNOWN';

    UPDATE gene
    SET biotype = 'protein_coding'
      , status = 'PREDICTED'
    WHERE biotype = 'processed_transcript'
      AND status = 'PREDICTED';

    UPDATE gene
    SET biotype = 'protein_coding'
      , status = 'PREDICTED'
    WHERE biotype = 'predicted_gene'
      AND status = 'UNKNOWN';

   UPDATE gene
    SET biotype = 'transcribed_pseudogene'
    WHERE biotype = 'expressed_pseudogene';

   UPDATE transcript
    SET biotype = 'transcribed_pseudogene'
    WHERE biotype = 'expressed_pseudogene';



    UPDATE transcript
    SET biotype = 'processed_transcript'
      , status = 'UNKNOWN'
    WHERE biotype = 'processed_transcript'
      AND status = 'NOVEL';


UPDATE transcript
SET biotype = 'processed_transcript', status = 'UNKNOWN'
WHERE biotype = 'novel_transcript';
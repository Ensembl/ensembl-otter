-- Copyright [2018-2019] EMBL-European Bioinformatics Institute
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--      http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.



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


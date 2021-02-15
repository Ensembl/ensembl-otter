-- Copyright [2018-2021] EMBL-European Bioinformatics Institute
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

insert into dna(dna_id,sequence) values(1,"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");

insert into clone(clone_id,name,embl_acc,version,embl_version,htg_phase,created,modified) values(1,'AC003663','AC003663',1,21,4,"2000-11-30 13:05:37","2000-11-30 13:05:37");

insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values(1,'pog',1,215,1,1);

insert into chromosome(chromosome_id,name) values(null,'CHR');

insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values(1,1,215,'CTG',1,215,1,1,1,215,1,'test_otter');

insert into meta(meta_id,meta_key,meta_value) values(2,"assembly.default","test_otter");

insert into dna(dna_id,sequence) values(2,"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
insert into dna(dna_id,sequence) values(3,"ATTTTTTTTTA"); 
insert into dna(dna_id,sequence) values(4,"A");
insert into dna(dna_id,sequence) values(5,"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
insert into dna(dna_id,sequence) values(6,"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTT");
insert into dna(dna_id,sequence) values(7,"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");

insert into clone(clone_id,name,embl_acc,version,embl_version,htg_phase,created,modified) values(50,'clone2','emacc2',1,1,4,"2000-11-30 13:05:37","2000-11-30 13:05:37");
insert into clone(clone_id,name,embl_acc,version,embl_version,htg_phase,created,modified) values(51,'clone3','emacc3',1,1,4,"2000-11-30 13:05:37","2000-11-30 13:05:37");

insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values(2,'contig2',50,30,1,2);
insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values(3,'contig3',50,11,1,3);
insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values(4,'contig4',50,1,1,4);
insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values(5,'contig5',50,30,1,5);
insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values(6,'contig6',50,30,1,6);
insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values(7,'contig7',51,30,1,7);

insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values(1,1,30,'CTG',1,30,1,2,1,30,1,'test_assem');
insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values(1,31,39,'CTG',31,39,1,3,2,10,-1,'test_assem');
insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values(1,40,40,'CTG',40,40,1,4,1,1,1,'test_assem');
insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values(1,41,70,'CTG',41,70,1,5,1,30,1,'test_assem');
insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values(1,71,100,'CTG',71,100,1,6,1,30,-1,'test_assem');
insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values(1,101,130,'CTG',101,130,1,7,1,30,1,'test_assem');

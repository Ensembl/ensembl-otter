EO=/software/anacode/otter/otter_production_main/ensembl-otter

DATASET=rat


if [ "$DATASET" = "human" ]; then
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_cdna_db_head           -satdbname homo_sapiens_cdna_78_38
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head           -satdbname homo_sapiens_core_78_38
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head_variation -satdbname homo_sapiens_variation_78_38
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_estgene_db_head        -satdbname homo_sapiens_otherfeatures_78_38

    # human:
    mysql -h otterlive --port 3324 -u ottadmin -p --database "loutre_$DATASET" -e "update meta set meta_value = \"my \$h='ens-livemirror.internal.sanger.ac.uk'; '-user'=>'ensro', '-host'=>\$h, '-dbname'=>'homo_sapiens_funcgen_78_38', '-port'=>3306, '-dnadb_user'=>'ensro', '-dnadb_host'=>\$h, '-dnadb_name'=>'homo_sapiens_core_78_38', '-dnadb_port'=>3306\" where meta_key = 'ensembl_funcgen_db_head' limit 1"


    # # human_dev:
    # # mysql -h otterpipe2 --port 3323 -u ottadmin -p --database jgrg_human_dev -e "update meta set meta_value = \"my \$h='ens-livemirror.internal.sanger.ac.uk'; '-user'=>'ensro', '-host'=>\$h, '-dbname'=>'homo_sapiens_funcgen_78_38', '-port'=>3306, '-dnadb_user'=>'ensro', '-dnadb_host'=>\$h, '-dnadb_name'=>'homo_sapiens_core_78_38', '-dnadb_port'=>3306\" where meta_key = 'ensembl_funcgen_db_head' limit 1"

    # mysql -h otterpipe2 --port 3323 -u ottro --database jgrg_human_dev -e 'select * from meta where meta_value like "%ens-livemirror%"'

    # # human_test:
    # # mysql -h otterpipe2 --port 3323 -u ottadmin -p --database jgrg_human_test -e "update meta set meta_value = \"my \$h='ens-livemirror.internal.sanger.ac.uk'; '-user'=>'ensro', '-host'=>\$h, '-dbname'=>'homo_sapiens_funcgen_78_38', '-port'=>3306, '-dnadb_user'=>'ensro', '-dnadb_host'=>\$h, '-dnadb_name'=>'homo_sapiens_core_78_38', '-dnadb_port'=>3306\" where meta_key = 'ensembl_funcgen_db_head' limit 1"

    # mysql -h otterpipe2 --port 3323 -u ottro --database jgrg_human_test -e 'select * from meta where meta_value like "%ens-livemirror%"'
fi


if [ "$DATASET" = "mouse" ]; then
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_cdna_db_head           -satdbname mus_musculus_cdna_78_38
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head           -satdbname mus_musculus_core_78_38
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_estgene_db_head        -satdbname mus_musculus_otherfeatures_78_38
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_rnaseq_db              -satdbname mus_musculus_rnaseq_78_38
fi


if [ "$DATASET" = "zebrafish" ]; then
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head           -satdbname danio_rerio_core_78_9
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_estgene_db_head        -satdbname danio_rerio_otherfeatures_78_9
fi


# # 77_240 & 78_245 have same assembly.default
if [ "$DATASET" = "c_elegans" ]; then
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head           -satdbname caenorhabditis_elegans_core_78_245
fi


# cat     - no keys
# chicken - no keys
# chimp   - no keys


if [ "$DATASET" = "cow" ]; then
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head           -satdbname bos_taurus_core_78_31
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_estgene_db_head        -satdbname bos_taurus_otherfeatures_78_31
fi


# dog     - no keys


if [ "$DATASET" = "drosophila" ]; then
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head           -satdbname drosophila_melanogaster_core_78_546
fi


# gibbon      - no keys
# gorilla     - no keys
# lemur       - no keys
# marmoset    - no keys
# medicago    - no keys
# mus_spretus - no keys
# opossum     - no keys


if [ "$DATASET" = "pig" ]; then
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head           -satdbname sus_scrofa_core_78_102
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_estgene_db_head        -satdbname sus_scrofa_otherfeatures_78_102
fi


# platypus    - no keys


if [ "$DATASET" = "rat" ]; then
    $EO/scripts/lace/save_satellite_db -dataset $DATASET -key ensembl_core_db_head           -satdbname rattus_norvegicus_core_78_5
fi


# sheep       - no keys
# sordaria    - no keys
# tas_devil   - no keys
# tomato      - no keys
# tropicalis  - no keys
# wallaby     - no keys


mysql -h otterlive --port 3324 -u ottro --database "loutre_$DATASET" -e 'select * from meta where meta_value like "%ens-livemirror%"'

exit

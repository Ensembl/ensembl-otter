#!/bin/sh

key="pipeline_db"
species_list=" 
  cat
  chicken
  chimp
  dog
  human
  mouse
  pig
  platypus
  rat
  wallaby
  zebrafish
  "

for species in $species_list
do
    ./save_satellite_db \
-dataset $species \
-key $key \
-sathost otterslave \
-satuser ottro \
-satport 3312 \
-satdbname ${species}_finished
done

#!/bin/bash

set -x

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$folder"/rawdata
mkdir -p "$folder"/processing

# url dato geografico
URL="https://github.com/pcm-dpc/COVID-19/raw/master/aree/geojson/dpc-covid-19-aree-nuove-g-json.zip"

# leggi la risposta HTTP del sito
code=$(curl -s -L -o /dev/null -w '%{http_code}' "$URL")

# se il sito è raggiungibile scarica e "lavora" i dati
if [ $code -eq 200 ]; then

  # scarica dati
  curl -kL "$URL" >"$folder"/rawdata/aree.zip

  # decomprimi i dati
  yes | unzip -j "$folder"/rawdata/aree.zip -d "$folder"/rawdata

  # estrai soltanto le geometrie corrispondenti alla versione più recente delle norme
  ogr2ogr -f geojson "$folder"/rawdata/aree_raw.geojson "$folder"/rawdata/dpc-covid-19-aree-nuove-g.json -dialect sqlite -sql 'select * from "dpc-covid-19-aree-nuove-g" where versionID IN (select max(CAST(versionID AS integer)) max from "dpc-covid-19-aree-nuove-g")' -lco RFC7946=YES

  # crea CSV di questo file
  ogr2ogr -f CSV "$folder"/rawdata/aree_raw.csv "$folder"/rawdata/aree_raw.geojson

  # crea CSV con informazioni di base e assegnazione zone
  mlr --csv cut -f nomeTesto,designIniz,designFine,nomeAutCom,legNomeBre,legData,legLink,legSpecRif,legLivello,legGU_Link \
    then clean-whitespace \
    then put -S '
if($legSpecRif=="art.1")
  {$zona="gialla"}
elif ($legSpecRif=="art.2")
  {$zona="arancione"}
elif ($legSpecRif=="art.3")
  {$zona="rossa"}
else
  {$zona="NA"}' "$folder"/rawdata/aree_raw.csv >"$folder"/processing/tmp_aree.csv

  # aggiungi al CSV codici NUTS
  mlr --csv join --ul -j nomeTesto -f "$folder"/processing/tmp_aree.csv \
    then unsparsify \
    then reorder -f nomeTesto,zona,NUTS_code,NUTS_level "$folder"/risorse/codici.csv >"$folder"/processing/aree.csv

  # semplifica il file geojson
  mapshaper "$folder"/rawdata/aree_raw.geojson -simplify dp 20% -o format=geojson "$folder"/processing/aree.geojson

  # aggiungi al geojson i codici NUTS
  mapshaper "$folder"/processing/aree.geojson -join "$folder"/risorse/codici.csv keys=nomeTesto,nomeTesto -o "$folder"/processing/tmp.geojson

  # aggiungi al geojson l'assegnazione delle zone
  ogr2ogr -f GeoJSON "$folder"/processing/aree.geojson "$folder"/processing/tmp.geojson -dialect sqlite -sql "
SELECT *,
CASE
WHEN legSpecRif = 'art.3' Then 'rossa'
WHEN legSpecRif = 'art.2' Then 'arancione'
WHEN legSpecRif = 'art.1' Then 'gialla'
ELSE 'NA' END as zona
from tmp"

  rm "$folder"/processing/tmp_aree.csv
  rm "$folder"/processing/tmp.geojson

fi
#!/bin/bash

###############################################################################
# This script will download FASTQ files from NCBI Sequence Read Archive (SRA)
##i#############################################################################

# If any errors are encountered, stop the pipeline
set -uo pipefail

# Check to make sure project and sample names are provided
if [[ -z ${PROJECT} ]] || [[ -z ${SAMPLES} ]] ; then
  echo "ERROR: Missing Project and/or Sample names." >&2
  exit 1
fi

# Change to the working directory
cd ${WORKING_DIR}

# Add the download from SRA step to the timelog file
echo "Downloading input FASTQs from the SRA at:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

echo "all samples: ${ALLSAMPLES}"

# Download fastq files from the SRA
for SAMPLE in ${ALLSAMPLES[@]}
   do \
      fasterq-dump \
      --split-3 \
      -t ${TEMP_DIR} \
      --progress --verbose \
      --skip-technical --rowid-as-name --print-read-nr \
      --threads=6 \
      --mem=200GB \
      --bufsize=1000MB \
      --curcache=1000MB \
      --force \
      --outdir data/raw-sra \
      ${SAMPLE}
   done

## Reset error checking + failing (this is after fasterq-dump because 'existing files' counts as a fail)
set -e

# Determine if single reads or paired-end reads for downstream processing
export PAIRED=0
export SINGLE=0

for SAMPLE in ${ALLSAMPLES[@]}
   do \
     if [[ -f data/raw-sra/${SAMPLE}.fastq ]]
       then let "SINGLE += 1"
     elif [[ -f data/raw-sra/${SAMPLE}_1.fastq ]] && \
        [[ -f data/raw-sra/${SAMPLE}_2.fastq ]]
        then let "PAIRED += 1"
     else
        echo "ERROR: cannot determine if input libraries are paired-end or" \
             "single-end. Exiting" >&2
       exit 2
     fi
   done

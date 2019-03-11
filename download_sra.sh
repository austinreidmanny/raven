#!/bin/bash

###############################################################################
# This script will download FASTQ files from NCBI Sequence Read Archive (SRA)
###############################################################################

# Check to make sure project and sample names are provided
if [[ -z ${PROJECT} ]] || [[ -z ${SAMPLES} ]] ; then
  then echo "ERROR: Missing Project and/or Sample names." >&2
  exit 1
fi

# Add the download from SRA step to the timelog file
echo "Downloading input FASTQs from the SRA at:" > \
analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# Download fastq files from the SRA
for SAMPLE in ${SAMPLES}
   do \
      fasterq-dump --split-3 -t ${TEMP_DIR} -p \
      -e 6 --skip-technical --rowid-as-name --mem=50GB \
      --outdir data/raw-sra \
      ${SAMPLE}
   done

# If any errors are encountered, stop the pipeline
## (this is after fasterq-dump because 'existing files' counts as a fail)
set -euo pipefail

# Determine if single reads or paired-end reads for downstream processing
export PAIRED=0
export SINGLE=0

for SAMPLE in ${SAMPLES}
   do if [[ -f data/raw-sra/${SAMPLE}.fastq ]]
      then let "SINGLE += 1"
   elif [[ -f data/raw-sra/${SAMPLE}_1.fastq ]] && \
        [[ -f data/raw-sra/${SAMPLE}_2.fastq ]]
      then let "PAIRED += 1"
   else
      echo "ERROR: cannot determine if input libraries are paired-end or" \
			     "single-end. Exiting" >&2
      exit 2
   fi; done

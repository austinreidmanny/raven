#!/bin/bash

################################################################################
# This script will assemble long contiguous sequences (contigs) from the raw
# raw reads from the FASTQ. These contigs will be much longer than the raw reads
# and will more accurately reflect the input nucleic acids
################################################################################

################################################################################
# Load necessary software from the cluster; if not on the cluster, ensure that
# python3 is available to call (i.e. in your PATH)
module load gcc/6.2.0 1>&2
module load python/3.6.0 1>&2
source ~/py3/bin/activate 1>&2
################################################################################

################################################################################
# Error checking
################################################################################
# If any step fails, the script will stop to prevent propogating errors
set -euo pipefail

# Check to make sure project and sample names are provided
if [[ -z "${PROJECT}" ]] || [[ -z "${SAMPLES}" ]] ;
  then echo "ERROR: Missing Project and/or Sample names." >&2
  exit 1
fi

# Make sure that rnaSPAdes is installed
command -v rnaspades.py || \
echo -e "ERROR: This script requires `rnaspades` but it could not found. \n" \
        "Please install this application. \n" \
        "Exiting with error code 6..." >&2; exit 6

# Make sure that python3 is installed
command -v python || \
echo -e "ERROR: This script requires `python3` but it could not found. \n" \
        "Please install this application. \n" \
        "Exiting with error code 6..." >&2; exit 6
################################################################################

################################################################################
# rnaSPAdes log info
echo "Began contig assembly at" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################

################################################################################
# Construct configuration file (YAML format) for input for rnaSPAdes
################################################################################
if [[ ${PAIRED} > 0 ]] && \
   [[ ${SINGLE} = 0 ]]
   then scripts/yaml_spades_pairedreads.sh ${ALL_SAMPLES}
elif [[ ${SINGLE} > 0 ]] && \
     [[ ${PAIRED} = 0 ]]
   then scripts/yaml_spades_singlereads.sh ${ALL_SAMPLES}
else
   echo -e "ERROR: could not build YAML configuration file for rnaSPAdes. \n" \
           "Possibly mixed input libraries: both single & paired end reads" >&2
   exit
fi
################################################################################

################################################################################
# Construct contigs from the raw reads using rnaSPAdes
################################################################################
rnaspades.py \
--threads 6 \
-m ${MAX_MEM} \
--tmp-dir ${TEMP_DIR} \
--dataset scripts/${SAMPLES}.input.yaml \
-o ${TEMP_DIR}
################################################################################

################################################################################
# Copy the results files from the temp directory to the working directory
################################################################################
cp ${TEMP_DIR}/transcripts.fasta data/contigs/${SAMPLES}.contigs.fasta
cp ${TEMP_DIR}/transcripts.paths data/contigs/${SAMPLES}.contigs.paths
cp ${TEMP_DIR}/spades.log analysis/contigs/${SAMPLES}.contigs.log
################################################################################

################################################################################
# rnaSPAdes log info
################################################################################
echo "Finished contig assembly at:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################

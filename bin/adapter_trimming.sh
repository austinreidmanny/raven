#!/bin/bash

################################################################################
# This script will automatically detect and remove adapter sequences from FASTQs
################################################################################

# If any step fails, the script will stop to prevent propogating errors
set -euo pipefail

################################################################################
# Load necessary software from the cluster; if not on the cluster, ensure that
# these Python and TrimGalore are available to call (i.e. in your PATH)
module load gcc/6.2.0 >&2
module load python/2.7.12 >&2
module load trimgalore >&2
################################################################################

################################################################################
# Check to make sure project and sample names are provided
if [[ -z "${PROJECT}" ]] || [[ -z "${SAMPLES}" ]] ;
  then echo "ERROR: Missing Project and/or Sample names." >&2
  exit 1
fi
################################################################################

################################################################################
# Adapter trimming log info
echo "Began adapter trimming at" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################

################################################################################
# Check to see if seq library type has been set
# (step performed automatically if download_sra.sh script is used

if [[ -z ${PAIRED} ]] || [[ -z ${SINGLE} ]] ; then
  then echo "WARNING: Sequencing library type not automatically detected";

	# If library type is not automatically detected, check if lib type was
	# provided by the user
		while getopts ":l:" arg; do
      case ${arg} in
      	l ) # Take in the library typ
        	LIB_TYPE=${OPTARG}
          if [[ ${LIB_TYPE} == "paired" ]]; then
          	PAIRED=1; SINGLE=0;
          elif [[ ${LIB_TYPE} == "single" ]]; then
          	PAIRED=0; SINGLE=1
          else
	        	echo "ERROR: Library type must be 'paired' or 'single'. Exiting" >&2
            exit 3;
          fi;
          ;;

       * ) # If any other option given, exit
           echo -e "ERROR: Unexpected option given in command line. \n" \
					         "Only acceptable option is specifying library type: \n" \
									 "'./adapter_trimming.sh' \n" \
									 "or \n"
							     "'./adapter_trimming.sh -l paired' \n" \
								   "or \n" \
							     "'./adapter_trimming.sh -l single'" >&2
								exit 4;;
		  esac
    done
################################################################################

################################################################################
# Trim adapters from raw SRA files

## Run TrimGalore! in paired-end mode
if [[ ${PAIRED} > 0 ]] && \
   [[ ${SINGLE} = 0 ]]
   then for SAMPLE in ${ALL_SAMPLES}
            do trim_galore \
               --paired \
               --stringency 5 \
               --quality 1 \
               -o data/fastq-adapter-trimmed \
               data/raw-sra/${SAMPLE}_1.fastq \
               data/raw-sra/${SAMPLE}_2.fastq
            done

## Run TrimGalore! in single/unpaired-end mode
elif [[ ${SINGLE} > 0 ]] && \
     [[ ${PAIRED} = 0 ]]
     then for SAMPLE in ${ALL_SAMPLES}
               do trim_galore \
                  --stringency 5 \
                  --quality 1 \
                  -o data/fastq-adapter-trimmed \
                  data/raw-sra/${SAMPLE}.fastq
               done

else
   echo "ERROR: could not determine library type"
   echo "Possibly mixed input libraries: both single and paired end reads"
   exit 3
fi
################################################################################

################################################################################
# Adapter trimming log info
echo "Finished adapter trimming at" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################

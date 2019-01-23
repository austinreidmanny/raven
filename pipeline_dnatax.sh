#!/bin/bash

#SBATCH -t 01-23:59
#SBATCH -p medium
#SBATCH --mem=50G
#SBATCH -c 6
#SBATCH -o logs/slurm-%j.log
#SBATCH -e logs/slurm-%j.err

# SETUP THE COMPUTATIONAL ENVIRONMENT

# Load required programs
module load gcc/6.2.0
module load python/2.7.12
module load trimgalore
# note: also requires Diamond, rnaSPAdes, and seqtk

# Load my Python environment
#source ~/py3/bin/activate

####################################
# Enter project name [REQUIRED]
export PROJECT=""
#####################################

# Check to make sure project name is given above; if not, exit with error code 1
if [ -z "${PROJECT}" ]
  then echo "No PROJECT name given."
  echo "Please edit this parameter at top of the pipeline script"
  exit 1
fi

# Setup workspace directory structure (PROJECT/data analysis scripts)
##   Will run all the analysis in scratch space (maximum read/write speed)
##   Will allocate specific temp space that is deleted at end of job
##   Will save final results in a permanent space

export SAMPLES="${1}-${!#}"
export HOME_DIR=`pwd`
export WORKING_DIR="/n/scratch2/am704/nibert/${PROJECT}/"
export TEMP_DIR="/n/scratch2/am704/tmp/${PROJECT}/${SAMPLES}/"
export FINAL_DIR="/n/data1/hms/mbib/nibert/austin/${PROJECT}/"
export DIAMOND_DB_DIR="/n/data1/hms/mbib/nibert/diamond/nr"

mkdir -p ${WORKING_DIR}
mkdir -p ${TEMP_DIR}
mkdir -p ${FINAL_DIR}

# Change to the working directory
cd ${WORKING_DIR}

# Setup data subdirectory
mkdir -p data/contigs
mkdir -p data/raw-sra
mkdir -p data/fastq-adapter-trimmed

# Setup analysis subdirectory
mkdir -p analysis/timelogs
mkdir -p analysis/contigs
mkdir -p analysis/diamond
mkdir -p analysis/taxonomy
mkdir -p analysis/viruses

# Setup scripts subdirecotry
mkdir -p scripts

# Copy key scripts (taxonomy and yaml-config-builders) from HOME to WORKING dir
cp ${HOME_DIR}/diamondToTaxonomy.py scripts/
cp ${HOME_DIR}/yaml_spades_pairedreads.sh scripts/
cp ${HOME_DIR}/yaml_spades_singlereads.sh scripts/

# Check to make sure samples are given, in the form of 1+ SRA accession(s)
# If not, exit with error code 2
if [ -z "$1" ]
	then echo "No project/sample name is given."
        echo "Must specify one or more samples"
	echo "Usage: ./pipeline.sh SRX000001 [SRX00002] [SRX00003] [...]"
	echo "Exiting."
	exit 2
fi

# output exact command into the slurm log
echo $0 ${@}
cat $0

# WITH THE COMPUTATIONAL ENVIRONMENT SET UP, BEGIN THE ANALYSIS

# Initialize timelog file
echo "Downloading input FASTQs from the SRA at:" > analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# Download fastq files from the SRA
for SAMPLE in ${@}
   do \
      fasterq-dump --split-3 -t ${TEMP_DIR} -p \
      -e 6 --skip-technical --rowid-as-name --mem=50GB \
      --outdir data/raw-sra \
      ${SAMPLE}
   done

# If any errors are encountered, stop the pipeline
# (this is after fasterq-dump because 'existing files' counts as a fail)
set -euo pipefail

# Determine if single reads or paired-end reads for downstream processing
PAIRED=0
SINGLE=0
for SAMPLE in ${@}
   do if [ -f data/raw-sra/${SAMPLE}.fastq ]
      then let "SINGLE += 1"
   elif [ -f data/raw-sra/${SAMPLE}_1.fastq ] && \
        [ -f data/raw-sra/${SAMPLE}_2.fastq ]
      then let "PAIRED += 1"
   else
      echo "ERROR: cannot determine if input libraries are paired-end or single-end"
      exit
   fi; done

# Adapter trimming log info
echo "Began adapter trimming at" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# Trim adapters from raw SRA files
## Run TrimGalore! in paired-end mode
if [ ${PAIRED} > 0 ] && \
   [ ${SINGLE} = 0 ]
   then for SAMPLE in ${@}
            do trim_galore \
               --paired \
               --stringency 5 \
               --quality 1
               -o data/fastq-adapter-trimmed \
               data/raw-sra/${SAMPLE}_1.fastq \
               data/raw-sra/${SAMPLE}_2.fastq
            done

## Run TrimGalore! in single/unpaired-end mode
elif [ ${SINGLE} > 0 ] && \
     [ ${PAIRED} = 0 ]
     then for SAMPLE in ${@}
               do trim_galore \
                  --stringency 5 \
                  --quality 1
                  -o data/fastq-adapter-trimmed \
                  data/raw-sra/${SAMPLE}.fastq
               done

else
   echo "ERROR: could not determine library type"
   echo "Possibly mixed input libraries: both single and paired end reads"
   exit 3
fi

# Adapter trimming log info
echo "Finished adapter trimming at" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# Load Python3 for downstream steps
module load python/3.6.0
source ~/py3/bin/activate

# rnaSPAdes log info
echo "Began contig assembly at" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# Construct YAML input file for rnaSPAdes
if [ ${PAIRED} > 0 ] && \
   [ ${SINGLE} = 0 ]
   then scripts/yaml_spades_pairedreads.sh ${@}
elif [ ${SINGLE} > 0 ] && \
     [ ${PAIRED} = 0 ]
   then scripts/yaml_spades_singlereads.sh ${@}
else
   echo "ERROR: could not build YAML configuration file for rnaSPAdes"
   echo "Possibly mixed input libraries: both single and paired end reads"
   exit
fi

# Construct contigs from the raw reads using rnaSPAdes
rnaspades.py \
--threads 6 \
-m 50 \
--tmp-dir ${TEMP_DIR} \
--dataset scripts/${SAMPLES}.input.yaml \
-o ${TEMP_DIR}

# Copy the results files from the temp directory to the working directory
cp ${TEMP_DIR}/transcripts.fasta data/contigs/${SAMPLES}.contigs.fasta
cp ${TEMP_DIR}/transcripts.paths analysis/contigs/${SAMPLES}.contigs.paths
cp ${TEMP_DIR}/spades.log analysis/contigs/${SAMPLES}.contigs.log

# rnaSPAdes log info
echo "Finished contig assembly at:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# diamond log info
echo "Began taxonomic classification at:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# Do classification of the contigs with Diamond
mkdir -p diamond
diamond \
blastx \
--verbose \
--more-sensitive \
--threads 6 \
--db ${DIAMOND_DB_DIR} \
--query data/contigs/${SAMPLES}.contigs.fasta \
--out analysis/diamond/${SAMPLES}.nr.diamond.txt \
--outfmt 102 \
--max-hsps 1 \
--top 1 \
--tmpdir ${TEMP_DIR}

# diamond log info
echo "Finished taxonomic classification:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# taxonomy log info
echo "Beginning taxonomy conversion:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# Convert taxon IDs to full taxonomy strings
cd analysis/diamond/
../../scripts/diamondToTaxonomy.py ${SAMPLES}.nr.diamond.txt
mv ${SAMPLES}.nr.diamond.taxonomy.txt ../taxonomy/
cd ../../

# viral sequences log info
echo "Beginning taxonomy conversion:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log

# Extract viral sequences and save them to a new file
grep Viruses analysis/taxonomy/${SAMPLES}.nr.diamond.taxonomy.txt | \
cut -f 1 | \
seqtk subseq data/contigs/${SAMPLES}.contigs.fasta - > \
analysis/viruses/${SAMPLES}.viruses.fasta

# Print number of viral sequences 
echo "Number of viral contigs in ${SAMPLES}:"
grep "^>" analysis/viruses/${SAMPLES}.viruses.fasta | \
wc -l 

# Create a small token to indicate it finished correctly
echo "Finished entire pipeline for ${SAMPLES}" > completed.pipeline

# Copy results to final, permanent directory
rsync -az ${WORKING_DIR}/ ${FINAL_DIR}/  


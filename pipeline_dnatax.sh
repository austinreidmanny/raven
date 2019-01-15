#!/bin/bash

#SBATCH -t 01-23:59
#SBATCH -p medium
#SBATCH --mem=50G
#SBATCH -c 6
#SBATCH -o logs/slurm-%j.log
#SBATCH -e logs/slurm-%j.err

# Set up the environment
module load gcc/6.2.0
module load python/3.6.0
module load bwa
module load samtools
source ~/py3/bin/activate


#####################################################
# ENTER PROJECT NAME                                #
#                                                   #
# (this is the only parameter that needs to change) #
#                                                   #
export PROJECT=""     
#####################################################


# CHECK TO MAKE SURE A SAMPLE_NAME IS GIVEN. IF NOT, EXIT
if [ -z "$1" ]
	then echo "No project/sample name is given."
        echo "Must specify one or more samples"
	echo "Usage: ./pipeline.sh SRX000001 [SRX00002] [SRX00003] [...]"
	echo "Exiting."
	exit 1
fi

# output exact command into the slurm log
echo $0 ${@}
cat $0

# Make directory to save the results in
mkdir -p /n/scratch2/am704/nibert/${PROJECT}/sra
mkdir -p /n/scratch2/am704/nibert/${PROJECT}/${1}-${!#}
cd /n/scratch2/am704/nibert/${PROJECT}/${1}-${!#}

# Create directories needed for later analysis
mkdir -p /tmp/am704/${1}-${!#}
mkdir -p /n/scratch2/am704/tmp/${1}-${!#}

# Initialize log file
echo "Downloading the file at:" > ${1}-${!#}.pipeline.log
date >> ${1}-${!#}.pipeline.log

# Download fastq files from the SRA
for SAMPLE in ${@}
   do \
      fasterq-dump --split-3 -t /tmp/am704/${1}-${!#} -p \
      -e 6 --skip-technical --rowid-as-name --mem=50GB \
      --outdir /n/scratch2/am704/nibert/${PROJECT}/sra/ \
      ${SAMPLE}
   done

# If any errors are encountered, stop the pipeline
# (this is after fasterq-dump because 'existing files' counts as a fail)
set -euo pipefail

# Add QC step to log
#echo "Began quality control/trimming step at:" >> ${1}-${!#}.pipeline.log
#date >> ${1}-${!#}.pipeline.log

# rnaSPAdes log info
echo "Began rnaSPAdes at" >> ${1}-${!#}.pipeline.log
date >> ${1}-${!#}.pipeline.log

# Create directories needed for rnaSPAdes
mkdir -p rnaspades/

# Determine if single reads or paired-end reads for rnaSPAdes contig file
PAIRED=0
SINGLE=0
for SAMPLE in ${@}
   do if [ -f /n/scratch2/am704/nibert/${PROJECT}/sra/${SAMPLE}.fastq ]
      then let "SINGLE += 1"
   elif [ -f /n/scratch2/am704/nibert/${PROJECT}/sra/${SAMPLE}_1.fastq ] && \
        [ -f /n/scratch2/am704/nibert/${PROJECT}/sra/${SAMPLE}_2.fastq ]
      then let "PAIRED += 1"
   else
      echo "ERROR: cannot determine if input libraries are paired-end or single-end"
      exit
   fi; done

# Construct YAML input file for rnaSPAdes
if [ ${PAIRED} > 0 ] && \
   [ ${SINGLE} = 0 ]
   then ~/nibert/${PROJECT}/yaml_spades_pairedreads.sh ${@}
elif [ ${SINGLE} > 0 ] && \
     [ ${PAIRED} = 0 ]
   then ~/nibert/${PROJECT}/yaml_spades_singlereads.sh ${@}
else
   echo "ERROR: could not build YAML configuration file for rnaSPAdes"
   echo "Possibly mixed input libraries: both single and paired end reads"
   exit
fi

# Construct contigs from the raw reads using rnaSPAdes
rnaspades.py \
--threads 6 \
-m 50 \
--tmp-dir /tmp/am704/${1}-${!#} \
--dataset rnaspades/input.yaml \
-o /n/scratch2/am704/tmp/${1}-${!#}/

# Copy the results files from the tmp directory to the final permament directory
cp /n/scratch2/am704/tmp/${1}-${!#}/transcripts.fasta rnaspades/${1}-${!#}.contigs.fasta
cp /n/scratch2/am704/tmp/${1}-${!#}/transcripts.paths rnaspades/${1}-${!#}.contigs.paths
cp /n/scratch2/am704/tmp/${1}-${!#}/spades.log rnaspades/${1}-${!#}.rnaspades.log

# rnaSPAdes log info
echo "Finished rnaspades at:" >> ${1}-${!#}.pipeline.log
date >> ${1}-${!#}.pipeline.log

# Do classification of the contigs with Kraken
mkdir -p diamond
diamond \
blastx \
--verbose \
--more-sensitive \
--threads 6 \
--db /n/data1/hms/mbib/nibert/austin/diamond/nr \
--query rnaspades/${1}-${!#}.contigs.fasta \
--out diamond/${1}-${!#}.nr.diamond.txt \
--outfmt 102 \
--max-hsps 1 \
--top 1 \
--tmpdir /tmp/am704/${1}-${!#}

# Taxonomy analysis
cd diamond/
~/nibert/scripts/taxonomy/diamondToTaxonomy.py ${1}-${!#}.nr.diamond.txt
cd ../

# Create a small token to indicate it finished correctly
echo "Finished entire pipeline for ${1}-${!#}" > completed.pipeline

# Copy results to permanent /data1/ directory
cp -Rp /n/scratch2/am704/nibert/${PROJECT}/${1}-${!#} /n/data1/hms/mbib/nibert/austin/${PROJECT}/


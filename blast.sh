#!/bin/bash

#SBATCH -t 00-00:59
#SBATCH -p short
#SBATCH --mem=15G
#SBATCH -c 4

###############################################################################
# USAGE:
#
# ./blast.sh CONTIGS.FASTA VIRAL_QUERY.FASTA QUERY_TYPE
###############################################################################

###############################################################################
# OBJECTIVE
#
# This script is to be run after de novo assembly. 
# Simply provide three parameters: 
#   1. the name of the fasta file containing the contigs
#   2. the name of the fasta file containing your query sequence
#   3. query sequence type ('nucl' or 'prot') 
# 
# This bridges the gap of new viral sequences that are not yet in NR/NT.
###############################################################################

# Set up the environment
module load gcc/6.2.0
module load python/3.6.0
source ~/py3/bin/activate

# CHECK TO MAKE SURE THAT CONTIGS AND QUERY FILES ARE GIVEN. IF NOT, EXIT
if [[ -z "$1" || -z "$2" || -z "$3" ]]
	then echo "Contig file, virus query file and/or query type not provided"
	echo "Usage: ./blast.sh CONTIGS.FASTA VIRUS_QUERY.FASTA QUERY_TYPE"
	echo "Exiting."
	exit 1
fi

# Assign input files to variables
CONTIGS=$1
VIRUS_QUERY=$2
QUERY_TYPE=$3

# Check to make sure that QUERY_TYPE provided correctly so correct BLAST will be called
if [[ ${QUERY_TYPE} == 'nucl' ]]; then
        BLAST_TYPE='blastn'
        BLAST_TASK='blastn'

elif [[ ${QUERY_TYPE} == 'prot' ]]; then
        BLAST_TYPE='tblastn'
        BLAST_TASK='tblastn'

else 
        echo "QUERY_TYPE must be 'nucl' or 'prot'"
        echo "exiting"
        exit 2
        
fi

# Output exact commands into log file
echo $0 ${@}
cat $0

# Create a directory to run & store the BLAST files
mkdir -p blast

# Indicate that database creation is beginning
echo "Building BLAST database from given contigs" && date

# Create names for BLAST output file

## truncates file path, leaving just the filename itself
CONTIGS_FILE=${CONTIGS##*/}

## eliminates file extension, giving a cleaner name for blast
BLAST_NAME_CONTIGS=${CONTIGS_FILE%.*} 

## repeat for VIRUS_QUERY
VIRUS_QUERY_FILE=${VIRUS_QUERY##*/}
BLAST_NAME_VIRUS_QUERY=${VIRUS_QUERY%.*}

# Make BLAST db from contigs
makeblastdb \
-dbtype nucl \
-in ${CONTIGS} \
-title ${BLAST_NAME_CONTIGS} \
-out blast/${BLAST_NAME_CONTIGS}_db \
-logfile blast/${BLAST_NAME_CONTIGS}_makeblastdb.log

# Indicate that BLAST alignment is beginning
echo "BLAST alignment beginning" && date

# Run nucleotide blast
${BLAST_TYPE} \
-task ${BLAST_TASK} \
-db blast/${BLAST_NAME_CONTIGS}_db \
-query ${VIRUS_QUERY} \
-out blast/${BLAST_TYPE}.${BLAST_NAME_VIRUS_QUERY}.${BLAST_NAME_CONTIGS}.txt \
-evalue 10 \
-num_threads 4
#-outfmt "6 qseqid sseqid evalue " \
# -max_target_seqs 1 \
# -max_hsps 1 \

# Indicate time of completion
echo "Job finished at" && date

# Make a token to indicate the job finished correctly
echo "Finished BLAST (${BLAST_TYPE}), using ${VIRUS_QUERY} to query against ${CONTIGS}" >> \
blast/blast.complete


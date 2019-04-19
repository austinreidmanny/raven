#!/bin/bash

###############################################################################################
# ENSURE THE PIPELINE IS CALLED CORRECTLY
###############################################################################################

# Set up a usage statement in case this program is called incorrectly
usage() { echo -e "\nERROR: Missing SRA accessions and/or input query and/or query type. \n\n" \
              "Make sure to provide one (or more) SRA run numbers separated by commas, \n" \
              "as well as a virus query (in fasta format), and indicate the query type \n" \
              "as either 'nucl' or 'prot' (do not include the quotes). \n\n" \
              "Proper usage: \n" \
              "$0 -s SRR10001,SRR10002,SRR... -q VIRUS_QUERY -t nucl|prot \n\n" \
              "Optional parameters: \n" \
                                   "-e (evalue, e.g. 100, 1, or 1e-99) \n" \
                                   "-dc (sets program to discontiguous-megablast) \n" \
                                   "-blastn (sets program to blastn) \n\n" \
              "Example of a complex run: \n" \
              "./run_blast_vdb.sh -s SRX193147,SRX193148,SRX193149 -q tvv2_nt.fasta -t nucl -e 1e-3 -dc \n\n" \
              "Exiting..." >&2; exit 1; }

# Make sure the pipeline is invoked correctly, with project and sample names
while getopts "s:q:t:e:dn" arg; do
        case ${arg} in
                s ) # Take in the sample name(s)
                  set -f
                  IFS=","
                  ALL_SAMPLES=(${OPTARG}) # call this when you want every individual sample
                        ;;
                q ) # Take in the name of the virus query file (fasta format)
                  VIRUS_QUERY=${OPTARG}
                        ;;
                t ) # Take in the query type (nucleotide or protein)
                  QUERY_TYPE=${OPTARG}
                        ;;
                e) # set evalue
                  E_VALUE=${OPTARG}
                        ;;
                d) # switch to discontiguous_megablast
                  BLAST_TASK="dc_megablast"
                        ;;
                n) # switch to blastn
                  BLAST_TASK="blastn"
                        ;;
                * ) # Display help
                  usage
                        ;;
        esac
done
shift $(( OPTIND-1 ))

################################################################################################
# PROCESS THE USER PROVIDED PARAMETERS
################################################################################################

# If the pipeline is not called correctly, tell that to the user and exit
if [[ -z "${VIRUS_QUERY}" ]] || [[ -z "${ALL_SAMPLES}" ]] || [[ -z "${QUERY_TYPE}" ]] ; then
        usage
fi

# Retrieve the name of last sample (using older but cross-platform compatible BASH notation)
LAST_SAMPLE=${ALL_SAMPLES[${#ALL_SAMPLES[@]}-1]}

# Create a variable that other parts of this pipeline can use mostly for naming
SAMPLES="${ALL_SAMPLES[0]}-${LAST_SAMPLE}"

# Format the SRA accessions correctly for BLAST db creation
DB_SAMPLES=`echo "\"${ALL_SAMPLES[@]}\""`

# Reset global expansion
set +f

# Handle the query type provided by the user, using that to determine which type of blast to use
## Nucleotide query
if [[ ${QUERY_TYPE} == 'nucl' ]]; then
    BLAST_TYPE='blastn_vdb'
    
    # If -d (dc_megablst) or -n (blastn) flags were no given by user, default to megablast
    if [[ -z "${BLAST_TASK}" ]]; then 
        BLAST_TASK='megablast'
    fi

## Protein query
elif [[ ${QUERY_TYPE} == 'prot' ]]; then
    BLAST_TYPE='tblastn_vdb'
    BLAST_TASK='tblastn'

## Other/Error
else
        echo "QUERY_TYPE is ${QUERY_TYPE}" 
        echo "QUERY_TYPE must be 'nucl' or 'prot' (do not include quotes)"
        usage 
fi

# If e-value wasn provided by user, then set it to 1e-9
if [[ -z ${E_VALUE} ]]; then
    E_VALUE="1e-9"
fi

################################################################################
# CREATE DIRECTORIES AND PREPARE NAMES FOR BLAST
################################################################################

# Create a directory to run & store the BLAST files
mkdir -p ${SAMPLES}

# Create names for BLAST output file

## truncates file path, leaving just the filename itself
VIRUS_QUERY_FILE=${VIRUS_QUERY##*/}

## eliminates file extension, giving a cleaner name for blast
BLAST_NAME_VIRUS_QUERY=${VIRUS_QUERY_FILE%.*}

# Create log file
set -o errexit
readonly LOG_FILE="${SAMPLES}/${BLAST_TYPE}.${SAMPLES}.${BLAST_NAME_VIRUS_QUERY}.log"
touch ${LOG_FILE}

# Read inputs back to the user and store them in the log
echo -e "\n" \
        "SRA Accessions provided: ${ALL_SAMPLES[@]} \n" \
        "Virus query file provided: ${VIRUS_QUERY} \n" \
        "Molecule type (nucl or prot) of input query: ${QUERY_TYPE} \n" \
        "e-value: ${E_VALUE} \n" \
        "Blast program: ${BLAST_TYPE} > ${BLAST_TASK} \n" | tee ${LOG_FILE}

###############################################################################
# RUN BLAST
################################################################################

# Print time started and write to log file
echo "Began running ${BLAST_TYPE} with samples ${SAMPLES} at:" | tee ${LOG_FILE}
date | tee -a ${LOG_FILE}

# Run blastn_vdb
${BLAST_TYPE} \
-task ${BLAST_TASK} \
-db ${DB_SAMPLES} \
-query ${VIRUS_QUERY} \
-out ${SAMPLES}/blastn_vdb.${SAMPLES}.${BLAST_NAME_VIRUS_QUERY}.txt \
-outfmt "6 qseqid evalue sseqid sseq" \
-num_threads 8 \
-evalue 1e-9 \
-max_target_seqs 100000000

# Print time completed and write to log file as well
echo "Finished running ${BLAST_TYPE} at:" | tee -a ${LOG_FILE}
date | tee -a ${LOG_FILE}

############################################################################################
# Create FASTA sequence file of hits
############################################################################################

awk '{print ">"$3"\n"$4}' ${SAMPLES}/blastn_vdb.${SAMPLES}.${BLAST_NAME_VIRUS_QUERY}.txt > \
    ${SAMPLES}/blastn_vdb.${SAMPLES}.${BLAST_NAME_VIRUS_QUERY}.fasta


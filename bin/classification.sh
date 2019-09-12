#!/bin/bash

function usage() {
    #==== FUNCTION ================================================================================#
    #        NAME: usage
    # DESCRIPTION: setup a usage statement that will inform the user how to correctly invoke the
    #              program
    #==============================================================================================#

    echo -e "\nERROR: Missing input files. \n" \
            "Make sure to provide path to samples \n\n" \
            "Usage for finding taxonomic origin of sequences in a single FASTA file: \n\n" \
             "$0 -f ./sequences.fasta \n\n" \
            "Optional parameters: \n" \
                  "-d (path to DIAMOND database [e.g., 'path/to/diamond_nr'] " \
                      "[default=none; download & set up NCBI nr database]) \n" \
                  "-o (directory for saving the files at the end; [default=current folder]) \n" \
                  "-m (maximum amount of memory to use [in GB]; [default=16] ) \n" \
                  "-n (number of CPUs/processors/cores to use; [default=use all available]) \n" \
                  "-t (temporary directory for storing temp files; [default='/tmp/']) \n" \
            "Example of a complex run: \n" \
            "$0 -f research/data/sequences.fasta -d tools/diamond/nr -m 32 -n 6 -t /tmp/ \n\n" \
            "Exiting program. Please retry with corrected parameters..." >&2; exit 1;
}

#==================================================================================================#
# Make sure the pipeline is invoked correctly, with project and sample names
#==================================================================================================#
    while getopts "f:d:o:m:n:t:" arg;
        do
        	case ${arg} in

                f ) # Path to input file
                    INPUT_FILE=${OPTARG}
                    SAMPLE_NAME=$(basename "${INPUT_FILE}" .fasta)
                        ;;

                d ) # Path to diamond directory & associated taxonomy files
                    DIAMOND_DB=${OPTARG}
                    DIAMOND_DB_DIR=$(dirname "${DIAMOND_DB}")
                        ;;

                o ) # Path to output directory for saving final files
                    OUTPUT_DIRECTORY=${OPTARG}
                        ;;

                m ) # set max memory to use (in GB; if any letters are entered, discard those)
                    MEMORY_ENTERED=${OPTARG}
                    MEMORY_TO_USE=$(echo $MEMORY_ENTERED | sed 's/[^0-9]*//g')
                        ;;

                n ) # set number of CPUs to use
                    NUM_THREADS=${OPTARG}
                        ;;

                t ) # set temporary directory (put in a random subdirectory to avoid conflicts if running in parallel)
                    TEMP_DIR=${OPTARG}/${RANDOM}
                        ;;

                * ) # Display help
        		    usage
        		     	;;
        	esac
        done; shift $(( OPTIND-1 ))


    #==============================================================================================#
    # Make sure input file exists and is a fasta file
    #==============================================================================================#
    if [[ -z ${INPUT_FILE} ]]; then
        usage
    fi

    if [[ ! -f ${INPUT_FILE} ]]; then
        echo "${INPUT_FILE} does not exist."
        usage
    fi

    if [[ ${INPUT_FILE} != *.fasta ]]; then
        echo -e "Input file does not appear to be in fasta format. \n"
                "Check provided file, and ensure the filename ends in '.fasta' \n"
        usage
    fi

    #==============================================================================================#
    # Output directory
    #==============================================================================================#

    # Create an output directory to store the output files
    ## If user didn't provide one, just use a subdirectory in working directory
    if [[ -z ${OUTPUT_DIRECTORY} ]]; then
        OUTPUT_DIRECTORY="./"
        mkdir -p ${OUTPUT_DIRECTORY}

    else
        # If user provided a desired output directory: check to make sure output directory doesn't exist;
        # then create output directory; if error, just default to a results subdirectory within current dir
        if [[ ! -d ${OUTPUT_DIRECTORY} ]]; then
            mkdir -p ${OUTPUT_DIRECTORY} || \
            {
                echo "Cannot create user-provided output directory. Defaulting to current working directory './'"
                OUTPUT_DIRECTORY="./"
                mkdir ${OUTPUT_DIRECTORY}
            }
        fi
    fi

    # If user didn't provide out dir, then check to see if there's an
    # SRA_DIR environmental variable, which I set on the lab iMac; if not, just use current directory
    if [[ -z "${OUTPUT_DIRECTORY}" ]]; then
        if [[ ! -z "${SRA_DIR}" ]]; then
            OUTPUT_DIRECTORY=${SRA_DIR}
        else
            OUTPUT_DIRECTORY="./"
        fi
    fi

    # Create the output directory; if there is an error in creating in, then exit
    mkdir -p ${OUTPUT_DIRECTORY} || \
        { echo "Cannot create directory. Choose different output directory and retry." \
             "Exiting..." && exit 2
         }

    #==============================================================================================#
    # Temporary directory
    #==============================================================================================#

    # Create the temporary directory. If user provided one, try to use that
    ## If user didn't provide a temporary directory, or if temporary directory cannot be created,
    ## defeault to "/tmp/"

    if [[ -z "${TEMP_DIR}" ]]; then
     TEMP_DIR="./"
     mkdir -p ${TEMP_DIR}

    else
     if [[ ! -d ${TEMP_DIR} ]]; then
         mkdir -p ${TEMP_DIR} || \
         {
             echo "Cannot create user-provided temporary directory. Defaulting to '/tmp/'"
             OUTPUT_DIRECTORY="/tmp/"
         }
     fi


    #==============================================================================================#
    # Set up number of CPUs to use and RAM
    #==============================================================================================#
    # CPUs (aka threads aka processors aka cores):
    ## If provided by user, use that. Otherwise:
    ## Use `nproc` if installed (Linux or MacOS with gnu-core-utils); otherwise use `sysctl`
    if [[ -z "${NUM_THREADS}" ]] ; then
        {   command -v nproc > /dev/null && \
            NUM_THREADS=$(nproc) && \
            echo "Number of processors available (according to nproc): ${NUM_THREADS}"; \
            } \
        || \
        {   command -v sysctl > /dev/null && \
            NUM_THREADS=$(sysctl -n hw.ncpu) && \
            echo "Number of processors available (according to sysctl): ${NUM_THREADS}";
            }
    fi
    #==============================================================================================#
    # Set memory usage to 16GB if none given by user
    if [[ -z ${MEMORY_TO_USE} ]]; then
        echo "No memory limit set by user. Defaulting to 16GB"
        MEMORY_TO_USE="16"
    fi

    # As a check to the user, print the project name and sample numbers to the screen
    echo -e "Input sequences provided: ${INPUT_FILE} \n" \
            "Memory to use: ${MEMORY_TO_USE} \n" \
            "Number of processors to use: ${NUM_THREADS} \n" | tee -a ${SAMPLE_NAME}.classification.log
#==================================================================================================#

function classification() {
    #==============================================================================================#
    # This function uses DIAMOND to taxonomically classify the contigs built by rnaSPAdes in
    # the previous de_novo_assembly step. In essence, DIAMOND works as an optimized BLASTx,
    # translating each contig into all coding frames and finding the closest match in the reference
    # database. Please specify the location of the DIAMOND reference database with the variable
    # DIAMOND_DB_DIR in the setup code block at the top.
    #==============================================================================================#

    #==============================================================================================#
    # Check that DIAMOND is installed, that the DIAMOND db is available, and that all required NCBI
    # taxonomy files are downloaded and present in the same directory as the DIAMOND db
    #==============================================================================================#
    # Make sure that DIAMOND is installed
    command -v diamond > /dev/null || \
    {   echo -e "ERROR: This script requires 'diamond' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6
        }

    # Check that the DIAMOND database is functional
    # if not present or if corrupt, download NCBI-NR fasta and make a DIAMOND db
    diamond dbinfo -d ${DIAMOND_DB} || {

       echo -e "\nERROR: Missing Diamond database. \n" \
               "Downloading NCBI NR database and necessary NCBI taxonomy information, and using these \n" \
               "to make new DIAMOND db now. May take a while... \n" \
               "Otherwise, quit (CTRL+C) and specify the directory containing all 3 files (db, taxonnodes, taxonmaps)" \
               "with the '-d' flag. \n\n" >&2

        # Download DIAMOND NR db and taxonomy files
        mkdir -p ${TEMP_DIR}/diamond_db/
        wget -O ${TEMP_DIR}/diamond_db/nr.gz ftp://ftp.ncbi.nlm.nih.gov/blast/db/FASTA/nr.gz

       # Download NCBI taxonomy files
        wget -O ${TEMP_DIR}/diamond_db/prot.accession2taxid.gz \
            ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/accession2taxid/prot.accession2taxid.gz
        wget -O ${TEMP_DIR}/diamond_db/taxdmp.zip \
            ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdmp.zip

        # Make DIAMOND db and point the directory variables to the new files
        diamond makedb \
        --in ${TEMP_DIR}/diamond_db/nr.gz \
        -d ${TEMP_DIR}/diamond_db/nr \
        --taxonmap ${TEMP_DIR}/diamond_db/prot.accession2taxid.gz \
        --taxonnodes ${TEMP_DIR}/diamond_db/taxdmp.zip

        DIAMOND_DB_DIR="${TEMP_DIR}/diamond_db"
        DIAMOND_DB="${DIAMOND_DB_DIR}/nr"
        NEW_DIAMOND_DB="TRUE"
        }

    #==============================================================================================#
    # A note about DIAMOND databases and taxonomy files
    #==============================================================================================#
    # If DIAMOND is run in taxonomy mode (102), working with a without the necessary NCBI taxonomy
    # files without these files, DIAMOND will fail. However, DIAMOND does not provide a way to check
    # whether or not a given database was built with this NCBI taxonomy info
    #
    # The only way I can think to deal with this is to check if the taxonomy files are available
    # in the same directory as the DIAMOND db. If not, I will assume that the database was not built
    # with those and thus will fail upon starting.

    # With that assumption, if the taxonomy files are not avilable, I will just download the NCBI
    # NR fasta, download the NCBI taxonomy info, and build a new database to use
    #==============================================================================================#

     # Check for both required NCBI taxonomy files; if at least one isn't there, just download both
    if [[ ! -f "${DIAMOND_DB_DIR}/prot.accession2taxid.gz" ]] || \
       [[ ! -f "${DIAMOND_DB_DIR}/taxdmp.zip" ]]; then
       echo -e "\nERROR: Necesary NCBI taxonomy files were not found in the same directory as the \n" \
               "DIAMOND database. This implies that the provided DIAMOND database was not built \n" \
               "with the proper taxonomy information. Will default to the NCBI NR database. \n\n" \
               "Downloading NCBI NR database and necessary NCBI taxonomy information, and using these \n" \
               "to make new DIAMOND db now. May take a while... \n\n" \
               "Otherwise, quit (CTRL+C) and specify the full path to the DIAMOND database with the '-d' flag \n" \
               "and ensure that the taxonnodes and taxonmaps are present in the same directory." \
               "\n\n" >&2

        # Download DIAMOND NR db and taxonomy files
        mkdir -p ${TEMP_DIR}/diamond_db/
        wget -O ${TEMP_DIR}/diamond_db/nr.gz ftp://ftp.ncbi.nlm.nih.gov/blast/db/FASTA/nr.gz

       # Download NCBI taxonomy files
        wget -O ${TEMP_DIR}/diamond_db/prot.accession2taxid.gz \
            ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/accession2taxid/prot.accession2taxid.gz
        wget -O ${TEMP_DIR}/diamond_db/taxdmp.zip \
            ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdmp.zip

        # Make DIAMOND db and point the directory variables to the new files
        diamond makedb \
        --in ${TEMP_DIR}/diamond_db/nr.gz \
        -d ${TEMP_DIR}/diamond_db/nr \
        --taxonmap ${TEMP_DIR}/diamond_db/prot.accession2taxid.gz \
        --taxonnodes ${TEMP_DIR}/diamond_db/taxdmp.zip

        DIAMOND_DB_DIR="${TEMP_DIR}/diamond_db"
        DIAMOND_DB="${DIAMOND_DB_DIR}/nr"
        NEW_DIAMOND_DB="TRUE"
    fi

    #==============================================================================================#

    #==============================================================================================#
    # DIAMOND log start
    #==============================================================================================#
    echo "Began taxonomic classification at:    $(date)" | \
        tee -a ${SAMPLE_NAME}.classification.log
    #==============================================================================================#

    #==============================================================================================#
    # Classify the contigs with Diamond
    #==============================================================================================#

    # A note on DIAMOND parameters
    #==============================================================================================#
    # Main determinants of memory usage are index-chunks and block-size.
    # Index-chunks should be set to 2 (good trade-off between speed & memory usage),
    # and block-size should be scaled to memory usage.
    # A conservative (read: safe) conversion is that each block uses 10 GB RAM.
    # If there is an issue with determining the optimal block-size, it will default to a
    # very small memory footprint that will work on 16GB system.
    #==============================================================================================#

    # try to scale it with memory available;  if that fails, set it to a very low, safe block-size
    { BLOCK_SIZE_TO_USE=$( expr ${MEMORY_TO_USE} / 10 )
        } &> /dev/null || \
    { BLOCK_SIZE_TO_USE=2
        }

    # Run diamond
    diamond \
    blastx \
    --verbose \
    --more-sensitive \
    --threads ${NUM_THREADS} \
    --db ${DIAMOND_DB} \
    --query ${INPUT_FILE} \
    --out ${OUTPUT_DIRECTORY}/${SAMPLE_NAME}.nr.diamond.txt \
    --outfmt 102 \
    --max-hsps 1 \
    --top 1 \
    --block-size ${BLOCK_SIZE_TO_USE} \
    --index-chunks 2 \
    --tmpdir ${TEMP_DIR}
    #==============================================================================================#
}

#==================================================================================================#
# Run the de novo aseembly
#==================================================================================================#
classification

#==================================================================================================#
# Program complete
#==================================================================================================#
echo -e "Successfully classified sequences based on taxonomic origin. \n" \
        "Files located at: ${OUTPUT_DIRECTORY}" | tee -a ${SAMPLE_NAME}.classification.log

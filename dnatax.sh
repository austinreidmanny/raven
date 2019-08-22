#!/bin/bash

#==================================================================================================#
# DNAtax
#==================================================================================================#
# This pipeline is be the driver script for DNAtax using the SLURM jobs manager
# Run this interactively by providing -p PROJECT & -s SRA-accs (full usage below)
#
# Full DNAtax pipeline downloads FASTQs from the NCBI-SRA, trims adapters,
# performs de novo contig assembly, determines the taxonomic origin of
# each sequence, translates these calls from NCBI TaxonIDs to full taxonomic
# lineages, extracts the viral sequences and saves them to its own FASTA file,
# and saves the results to a final permanent directory and cleans up.
#==================================================================================================#

#==================================================================================================#
# Initialize
#==================================================================================================#
# Stop program if it any component fails
set -eo pipefail

# Welcome user to DNAtax
echo -e "\n ================================================================================\n" \
           "Welcome to DNAtax! \n" \
           "================================================================================\n" \
           "Full source code & contact info available at github.com/austinreidmanny/dnatax  \n" \
           "================================================================================\n"

# Load environment containing all necessary software (prepared by the setup.sh script); if error, exit
eval "$(conda shell.bash hook)"
conda activate env_dnatax > /dev/null || {
   echo -e "Could not activate the conda environment for dnatax." \
           "Please fully run the setup.sh script, restart terminal, and try again."
   exit 10
   }
#==================================================================================================#

function usage() {
    #==== FUNCTION ================================================================================#
    #        NAME: usage
    # DESCRIPTION: setup a usage statement that will inform the user how to correctly invoke the
    #              program
    #==============================================================================================#

    echo -e "\n" \
    "ERROR: Missing project and/or sample names. \n" \
    "Make sure to provide a project name and one (or more) SRA run numbers separated by commas \n\n" \
    "Usage: $0 -p PROJECT -s SRR10001,SRR10002,SRR..." \
    "Optional parameters: \n" \
        "-l (library type of the reads; 'paired' or 'single'; [default=auto determine]) \n" \
        "-m (maximum amount of memory to use [in GB]; [default=16] ) \n" \
        "-n (maximum number of CPUs to use; [default=attempt to auto-determine; not perfect]) \n" \
        "-w (set the working directory, where all analysis will take place; [default=current directory, \n" \
            "but a scratch directory with a lot of storage is recommended]) \n" \
        "-f (set the final directory, where all the files will be copied to the end [default=current directory]) \n" \
        "-t (set the temporary directory, where the pipeline will dump all temp files [default='/tmp/dnatax/'] \n" \
        "-h (set the home directory where DNAtax is located; [default=current directory, is recommended not to change]) \n" \
        "-d (specify the full path to the DIAMOND database, including the db name - e.g., '/path/to/nr-database/nr' \n" \
            "[default=none, will download all files to temp space and copy them to final directory at the end; NOTE: \n" \
            "DNAtax requires a DIAMOND database, NCBI taxonmaps file, and NCBI protein2accessions file; \n" \
            "These all must be located in the same directory as the DIAMOND database \n\n" \
    "Example of a complex run: \n" \
    "$0 -p trichomonas -s SRR1001,SRR10002 -l paired -m 30 -w external_drive/storage/ -f projects/dnatax/final/ -t /tmp/ -d tools/diamond/nr \n\n" \
    "Exiting program. Please retry with corrected parameters..." >&2; exit 1;
    }

#==================================================================================================#
# Make sure the pipeline is invoked correctly, with project and sample names
#==================================================================================================#
    while getopts "p:s:l:m:n:w:f:t:h:d:" arg;
        do
            case ${arg} in
                p ) # Take in the project name
                    PROJECT=${OPTARG}
                    ;;

                s ) # Take in the sample name(s)
                    set -f
                    IFS=","
                    ALL_SAMPLES=(${OPTARG}) # call this when you want every individual sample
                    ;;

                l ) # Take in the library type ('paired' or 'single')
                    LIB_TYPE=${OPTARG}
                    if [[ ${LIB_TYPE} == "paired" ]]; then
                        LIB_TYPE="paired"
                    elif [[ ${LIB_TYPE} == "single" ]]; then
                        LIB_TYPE="single"
                    else
                        echo "ERROR: Library type must be 'paired' or 'single'. Exiting with error 3..." >&2
                        exit 3;
                    fi;
                    ;;

                m ) # set max memory to use (in GB; if any letters are entered, discard those)
                    MEMORY_ENTERED=${OPTARG}
                    MEMORY_TO_USE=$(echo $MEMORY_ENTERED | sed 's/[^0-9]*//g')
                    ;;

                n ) # set max number of CPUs/processors/cores to use
                    NUM_THREADS=${OPTARG}
                    ;;

                w ) # set working directory
                    WORKING_DIR=${OPTARG}
                    ;;

                f ) # set final directory
                    FINAL_DIR=${OPTARG}
                    ;;

                t ) # set temp directory
                    TEMP_DIR=${OPTARG}
                    ;;

                h ) # set home directory, where dnatax code is located; recommandation: don't change
                    HOME_DIR=${OPTARG}
                    ;;

                d ) # set path to Diamond database
                    DIAMOND_DB=${OPTARG}
                    DIAMOND_DB_DIR=$(dirname "${DIAMOND_DB}")
                    ;;

                * ) # Display help
        		    usage
        		    ;;
        	esac
        done; shift $(( OPTIND-1 ))

#==================================================================================================#
# Process names: use the user-provided parameters above to create variable names that can be
#                called in the rest of the pipeline
#==================================================================================================#

    # If the mandatory parameters (project and SRA accs) aren't provided, tell that to the user & exit
    if [[ -z "${PROJECT}" ]]  || [[ -z "${ALL_SAMPLES}" ]] ; then
     usage
    fi

    # Create a variable for naming [each SRA separated by underscore, unless there are too many samples]
    if [[ ${#ALL_SAMPLES[@]} -le 5 ]]; then
        SAMPLES=$(echo ${ALL_SAMPLES[@]} | sed 's/ /_/g')
    else
        # Retrieve name of the last sample (uses older but cross-platform compatible BASH notation)
        LAST_SAMPLE=${ALL_SAMPLES[${#ALL_SAMPLES[@]}-1]}

        # Create an abbreviated naming scheme of "SRR{first}-SRR{last}"
        SAMPLES="${ALL_SAMPLES[0]}-${LAST_SAMPLE}"
    fi

    # Reset global expansion [had to change to read multiple sample names]
    set +f

    # Check to see if all of the various directories were provided; if not, set the defaults
    if [[ -z "${HOME_DIR}" ]] ; then
        HOME_DIR=$(pwd)
    fi

    if [[ -z "${WORKING_DIR}" ]] ; then
        WORKING_DIR="./dnatax/"
    fi

    if [[ -z "${FINAL_DIR}" ]] ; then
        FINAL_DIR="./dnatax/"
    fi

    if [[ -z "${TEMP_DIR}" ]] ; then
        TEMP_DIR="/tmp/dnatax/${SAMPLES}"
    fi

    #==============================================================================================#
    # Set up number of CPUs to use and RAM
    #==============================================================================================#
    # CPUs (aka threads aka processors aka cores):
    ## Use `nproc` if installed (Linux or MacOS with gnu-core-utils); otherwise use `sysctl`
    if [[ -z "${NUM_THREADS}" ]] ; then
      { command -v nproc > /dev/null && \
        NUM_THREADS=$(nproc) && \
        echo "Number of processors available (according to nproc): ${NUM_THREADS}"; \
        } \
    || \
      { command -v sysctl > /dev/null && \
        NUM_THREADS=$(sysctl -n hw.ncpu) && \
        echo "Number of processors available (according to sysctl): ${NUM_THREADS}";
        }
    fi
    #==============================================================================================#
    # Set memory usage to 16GB if none given by user
    if [[ -z "${MEMORY_TO_USE}" ]]; then
        echo "No memory limit set by user. Defaulting to 16GB"
        MEMORY_TO_USE="16"
    fi

    # As a check to the user, print the pipeline parameters (project name, sample accesions, etc)
    echo "PROJECT name: ${PROJECT}"
    echo "SRA sample accessions: ${ALL_SAMPLES[@]}"
    echo "Memory limit: ${MEMORY_TO_USE}"
    echo "Number of CPUs: ${NUM_THREADS}"
    echo "Pipeline start time: $(date)"
#==================================================================================================#

#==================================================================================================#
# Set up project directory structure
#==================================================================================================#

    #   project-name/
    #    |_ dnatax/
    #        |_ data/
    #        |_ analysis/
    #        |_ scripts/

    # Will run all the analysis in scratch space (maximum read/write speed)
    # Will allocate specific temp space that is deleted at end of job
    # Will save final results in a permanent space

    # Create these directories
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

    # Copy dnatax pipeline & the key taxonomy script from HOME to WORKING dir
    if [[ -f ${HOME_DIR}/diamondToTaxonomy.py ]]
      then echo "All neccessary scripts are available to copy. COPYING...";
      cp ${HOME_DIR}/diamondToTaxonomy.py scripts/
      cp ${HOME_DIR}/$(basename $0) scripts/

    # If the scripts are not available to copy, then tell user where to download
    # them, then exit
    else
      echo -e "One or more of the following scripts are missing: \n" \
              "diamondToTaxonomy.py, $0" >&2
      echo "Please download this from github.com/austinreidmanny/dnatax" >&2
      echo "ERROR: Cannot find mandatory helper scripts. Exiting" >&2
      exit 1
    fi

    # Setup script has finished
    echo "Setup complete"
#==================================================================================================#

function determine_library_type() {
    #==============================================================================================#
    # If no library type is given by user, determine if single reads or paired-end reads by looking
    # at file naming scheme; SRA & fasterq-dump give specific naming scheme for paired vs. unpaired
    #==============================================================================================#

    # Check to make sure library type not provided by user, then set both paired and single to 0;
    # will read through list of fastq files and count how many are paired vs single-end based on
    # fasterq-dump's naming scheme

    if [[ -z ${LIB_TYPE} ]]; then
        PAIRED=0
        SINGLE=0

        for SAMPLE in ${ALL_SAMPLES[@]}
            do
                if [[ -f data/raw-sra/${SAMPLE}.fastq ]]
                    then let "SINGLE += 1"
                elif [[ -f data/raw-sra/${SAMPLE}_1.fastq ]] && \
                     [[ -f data/raw-sra/${SAMPLE}_2.fastq ]]
                     then let "PAIRED += 1"
                else
                    echo "ERROR: cannot determine if input libraries are paired-end or" \
            			     "single-end. Exiting" >&2; exit 2
                fi
            done

        ## Paired-end reads mode
        if [[ ${PAIRED} > 0 ]] && [[ ${SINGLE} = 0 ]];
            then LIB_TYPE="paired"

        ## Single-end reads mode
        elif [[ ${SINGLE} > 0 ]] && [[ ${PAIRED} = 0 ]];
            then LIB_TYPE="single"

        ## Otherwise, error
        else
             echo "ERROR: cannot determine if input libraries are paired-end or " \
                  "single-end. Exiting" >&2; exit 2
        fi
    fi
}

function download_sra() {
    #==============================================================================================#
    # Downloads the transcriptomes from the NCBI Sequence Read Archive (SRA)
    #==============================================================================================#

    #==============================================================================================#
    # Ensure that the necessary software is installed
    command -v fasterq-dump > /dev/null || \
    {   echo -e "ERROR: This script requires 'fasterq-dump' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2 && exit 6
        }
    #==============================================================================================#

    #==============================================================================================#
    # Add the download from SRA step to the timelog file
    echo "Downloading input FASTQs from the SRA at:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log

    # Disable error checking because fasterq-dump treats 'existing files' as a failure
    set +eo pipefail
    #==============================================================================================#

    #==============================================================================================#
    # Download fastq files from the SRA
    for SAMPLE in ${ALL_SAMPLES[@]}
       do \
          fasterq-dump \
          --split-3 \
          -t ${TEMP_DIR} \
          -e ${NUM_THREADS} \
          --mem=${MEMORY_TO_USE} \
          -p \
          --skip-technical \
          --rowid-as-name \
          --outdir data/raw-sra \
          ${SAMPLE}
       done
    #==============================================================================================#

    # Reset the error checking
    set -eo pipefail

    # Determine the library type of the downloaded reads (paired or unpaired reads)
    determine_library_type

    # Notify user that the reads have finished Downloading
   echo "finished downloading SRA files at:    $(date)" | \
       tee -a analysis/timelogs/${SAMPLES}.log
}

function adapter_trimming() {
    #==============================================================================================#
    # Trim adapters from raw SRA files
    #==============================================================================================#

    #==============================================================================================#
    # Ensure that the necessary software is installed
    command -v trim_galore > /dev/null || \
    {   echo -e "ERROR: This script requires 'trim_galore' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6
        }
    #==============================================================================================#

    #==============================================================================================#
    # Adapter trimming log info
    echo "Began adapter trimming at:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#

    #==============================================================================================#
    # Run TrimGalore! in paired or single end mode, depending on input library type
    #==============================================================================================#
    # Check to make sure library type has been set or determined
    if [[ -z "${LIB_TYPE}" ]]; then
        determine_library_type
    fi

    ## Paired-end mode
    if [[ ${LIB_TYPE} == "paired" ]]; then
        for SAMPLE in ${ALL_SAMPLES[@]}
            do trim_galore \
               --paired \
               --stringency 5 \
               --quality 1 \
               -o data/fastq-adapter-trimmed \
               data/raw-sra/${SAMPLE}_1.fastq \
               data/raw-sra/${SAMPLE}_2.fastq
            done

    ## Single/unpaired-end mode
    elif [[ ${LIB_TYPE} == "single" ]]; then
        for SAMPLE in ${ALL_SAMPLES[@]}
           do trim_galore \
              --stringency 5 \
              --quality 1 \
              -o data/fastq-adapter-trimmed \
              data/raw-sra/${SAMPLE}.fastq
           done

    ## If cannot determine library type, exit
    else
       echo -e "ERROR: could not determine library type" >&2 \
               "Possibly mixed input libraries: both single & paired-end reads" >&2
       exit 3
    fi
    #==============================================================================================#

    #==============================================================================================#
    # Adapter trimming log info
    echo "Finished adapter trimming at:    $(date)" | \
       tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#
}

function de_novo_assembly() {
    #==============================================================================================#
    # This function will assemble long contiguous sequences (contigs) from the raw
    # raw reads from the FASTQ. These contigs will be much longer than the raw reads
    # and will more accurately reflect the input nucleic acids
    #==============================================================================================#

    #==============================================================================================#
    # Error checking
    #==============================================================================================#
    # Make sure that rnaSPAdes is installed
    command -v rnaspades.py > /dev/null || \
    {   echo -e "ERROR: This script requires 'rnaspades' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6
        }

    # Make sure that python3 is installed
    command -v python3 > /dev/null || \
    {   echo -e "ERROR: This script requires 'python3' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6
        }
    #==============================================================================================#

    #==============================================================================================#
    # rnaSPAdes log info
    echo "Began contig assembly at:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#

    #==============================================================================================#
    # Construct configuration file (YAML format) for input for rnaSPAdes
    #==============================================================================================#
    if [[ ${LIB_TYPE} == "paired" ]]; then
        yaml_spades_pairedreads

    elif [[ ${LIB_TYPE} == "unpaired" ]]; then
        yaml_spades_singlereads

    else
       echo -e "ERROR: could not build YAML configuration file for rnaSPAdes. \n" \
               "Possibly mixed input libraries: both single & paired end reads" >&2
       exit
    fi
    #==============================================================================================#

    #==============================================================================================#
    # Construct contigs from the raw reads using rnaSPAdes
    #==============================================================================================#
    rnaspades.py \
    --threads ${NUM_THREADS} \
    -m ${MEMORY_TO_USE} \
    --tmp-dir ${TEMP_DIR} \
    --dataset scripts/${SAMPLES}.input.yaml \
    -o ${TEMP_DIR}
    #==============================================================================================#

    #==============================================================================================#
    # Filter out all contigs shorter than 300 nucleotides
    #==============================================================================================#
    seqtk seq \
    -L 300 \
    ${TEMP_DIR}/transcripts.fasta > \
    ${TEMP_DIR}/transcripts.filtered.fasta
    #==============================================================================================#

    #==============================================================================================#
    # Copy the results files from the temp directory to the working directory
    #==============================================================================================#
    cp ${TEMP_DIR}/transcripts.filtered.fasta analysis/contigs/${SAMPLES}.contigs.fasta
    cp ${TEMP_DIR}/transcripts.fasta analysis/contigs/${SAMPLES}.contigs.unfiltered.fasta
    cp ${TEMP_DIR}/transcripts.paths analysis/contigs/${SAMPLES}.contigs.paths
    cp ${TEMP_DIR}/spades.log analysis/contigs/${SAMPLES}.contigs.log
    #==============================================================================================#

    #==============================================================================================#
    # rnaSPAdes log info
    #==============================================================================================#
    echo "Finished contig assembly at:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#
}

function yaml_spades_singlereads() {
    #==============================================================================================#
    # This function creates configuration file for running rnaSPAdes in single/unpaired-reads mode.
    # It creates a YAML formatted config file that instructs rnaSPAdes about the library type
    # and name for each sample. Allows for greater flexibility for running rnaSPAdes than
    # just giving the program the name of the input files.
    #==============================================================================================#
    YAML_OUTPUT="scripts/${SAMPLES}.input.yaml"

    # Write beginning of the file
    echo '    [
          {
            type: "single",
            single reads: [' > ${YAML_OUTPUT}

    # For each SRX, write the location of the forward reads
    for SAMPLE in ${ALL_SAMPLES[@]}
       do
          echo -n \
          '          "../data/fastq-adapter-trimmed/' >> ${YAML_OUTPUT}
          echo \
          ${SAMPLE}_trimmed.fq\", >> ${YAML_OUTPUT}
       done

    # Remove the last comma
    sed '$ s/.$//' ${YAML_OUTPUT} > ${YAML_OUTPUT}.temp
    mv ${YAML_OUTPUT}.temp ${YAML_OUTPUT}

    # Write the last bit of formatting
    echo \
    '        ]
          },
         ]' >> ${YAML_OUTPUT}

    # Completion
    echo "Finished contructing single-read input yaml for ${SAMPLES}"
}

function yaml_spades_pairedreads() {
    #==============================================================================================#
    # This function creates configuration file for running rnaSPAdes in paired-reads mode.
    # It creates a YAML formatted config file that instructs rnaSPAdes about the library type
    # and name for each sample. Allows for greater flexibility for running rnaSPAdes than
    # just giving the program the name of the input files.
    #==============================================================================================#
    YAML_OUTPUT="scripts/${SAMPLES}.input.yaml"

    # Write beginning of the file
    echo '    [
          {
            orientation: "fr",
            type: "paired-end",
            left reads: [' > ${YAML_OUTPUT}

    # For each SRX, write the location of the forward reads
    for SAMPLE in ${ALL_SAMPLES[@]}
       do
          echo -n \
          '          "../data/fastq-adapter-trimmed/' >> ${YAML_OUTPUT}
          echo \
          ${SAMPLE}_1_val_1.fq\", >> ${YAML_OUTPUT}
       done

    # Remove the last comma
    sed '$ s/.$//' ${YAML_OUTPUT} > ${YAML_OUTPUT}.temp
    mv ${YAML_OUTPUT}.temp ${YAML_OUTPUT}

    # Write some more formatting
    echo \
    '        ],
            right reads: [' >> ${YAML_OUTPUT}

    # For each SRX, write the location of the reverse reads
    for SAMPLE in ${ALL_SAMPLES[@]}
       do
          echo -n \
          '          "../data/fastq-adapter-trimmed/' >> ${YAML_OUTPUT}
          echo \
          ${SAMPLE}_2_val_2.fq\", >> ${YAML_OUTPUT}
       done

    # Remove the last comma
    sed '$ s/.$//' ${YAML_OUTPUT} > ${YAML_OUTPUT}.temp
    mv ${YAML_OUTPUT}.temp ${YAML_OUTPUT}

    # Write last bit of formatting
    echo \
    '        ]
          },
         ]' >> ${YAML_OUTPUT}

    echo "Finished contructing input yaml for ${SAMPLES}"
}

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
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#

    #==============================================================================================#
    # Classify the contigs with Diamond
    #==============================================================================================#

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

    #==============================================================================================#
    # DIAMOND temporary directory
    #==============================================================================================#
    # Diamond will sporadically fail on Linux systems b/c it cannot access the temporary directory
    # Accoding to the devs, the safest thing to do is use ramdisk. On Linux systems, this is /dev/shm/
    # So if user is on a Linux system, use /dev/shm. If not, try our luck with the provided temp dir
    #==============================================================================================#
    if [[ -d /dev/shm/ ]]; then
        DIAMOND_TEMP_DIR="/dev/shm/"
    else
        DIAMOND_TEMP_DIR=${TEMP_DIR}
    fi
    #==============================================================================================#

    # Run diamond
    diamond \
    blastx \
    --verbose \
    --more-sensitive \
    --threads ${NUM_THREADS} \
    --db ${DIAMOND_DB} \
    --query analysis/contigs/${SAMPLES}.contigs.fasta \
    --out analysis/diamond/${SAMPLES}.nr.diamond.txt \
    --outfmt 102 \
    --max-hsps 1 \
    --top 1 \
    --block-size ${BLOCK_SIZE_TO_USE} \
    --index-chunks 2 \
    --tmpdir ${DIAMOND_TEMP_DIR}
    #==============================================================================================#

    #==============================================================================================#
    # DIAMOND log end
    echo "Finished taxonomic classification:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#
}

function taxonomy() {

    #==============================================================================================#
    # Check to make sure the diamondToTaxonomy.py script is available
    if [[ ! -f scripts/diamondToTaxonomy.py ]] ;
      then echo -e "ERROR: No diamondToTaxonomy.py script found. \nExiting..." >&2
      exit 5
    fi
    #==============================================================================================#

    #==============================================================================================#
    # Taxonomy log info
    #==============================================================================================#
    echo "Beginning taxonomy conversion:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#

    #==============================================================================================#
    # Convert taxon IDs to full taxonomy strings
    #==============================================================================================#
    cd analysis/diamond/
    ../../scripts/diamondToTaxonomy.py ${SAMPLES}.nr.diamond.txt
    mv ${SAMPLES}.nr.diamond.taxonomy.txt ../taxonomy/
    cd ../../
    #==============================================================================================#

    #==============================================================================================#
    # Taxonomy sequences log info
    #==============================================================================================#
    echo "Finished taxonomy conversion:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#
}

function mapping() {
    #==== FUNCTION ================================================================================#
    #        NAME: mapping
    # DESCRIPTION: map initial reads to the de novo assembled contigs and merge that as a new column
    #              onto the table containing all contigs and their taxonomic assignment
    #==============================================================================================#

    #==============================================================================================#
    # Preparation
    #==============================================================================================#
    # Create mapping directory for saving the results
    mkdir -p analysis/mapping
    mkdir -p analysis/mapping/processing

    # Create input and output file names
    taxonomy_table="analysis/taxonomy/${SAMPLES}.nr.diamond.taxonomy.txt"
    mapped_table="analysis/mapping/${SAMPLES}.nr.diamond.taxonomy.mapped.txt"

    # Check if paired-end or single-end reads
    if [[ -z ${LIB_TYPE} ]]; then
        determine_library_type
    fi

    # Make sure BWA was installed correctly
    command -v bwa > /dev/null || \
    {   echo -e "ERROR: This script requires the tool 'bwa' but could not found. \n" \
            "Please rerun the setup scirpt or install this application manually. \n" \
            "Exiting with error code 7..." >&2; exit 7
        }

    # Logging time of the mapping stage
    echo -e "Mapping reads to contigs, and constructing a final table with \n" \
            "contig names, taxonomic assignments, and coverage values at. Beginning at: \n" \
            "$(date)" | tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#

    #==============================================================================================#
    # Index the reference and map the reads
    #==============================================================================================#
    # Build BWA index out of the reference
    bwa index \
    -p analysis/mapping/processing/bwa-index_${SAMPLES} \
    analysis/contigs/${SAMPLES}.contigs.fasta

    # Perform the mapping

    ## paired-end input reads
    if  [[ ${LIB_TYPE} == "paired" ]]; then

        bwa mem \
        -t ${NUM_THREADS} \
        analysis/mapping/processing/bwa-index_${SAMPLES} \
        <(cat data/fastq-adapter-trimmed/*_1_val_1.fq) \
        <(cat data/fastq-adapter-trimmed/*_2_val_2.fq) > \
        analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.sam

    ## unpaired input reads
    elif [[ ${LIB_TYPE} == "single" ]]; then

         bwa mem \
         -t ${NUM_THREADS} \
         analysis/mapping/processing/bwa-index_${SAMPLES} \
         <(cat data/fastq-adapter-trimmed/*trimmed.fq) > \
         analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.sam

    else
       echo -e "ERROR: Could not map reads to contigs. \n" \
               "Possibly mixed input libraries: both single & paired end reads. \n" \
               "Exiting with error 8..." >&2
       exit 8
    fi
    #==============================================================================================#

    #==============================================================================================#
    # Get summary statistics of the mapping
    #==============================================================================================#
    samtools flagstat  \
    --threads $(expr ${NUM_THREADS}-1) \
    analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.sam > \
    analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.stats
    #==============================================================================================#

    #==============================================================================================#
    # Remove unmapped reads, sort the reads, and save it as a sorted+compressed bam file
    #==============================================================================================#
    samtools view \
        --threads $(expr ${NUM_THREADS}-1) \
        -F 4 -bh \
        analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.sam |
    samtools sort --threads $(expr ${NUM_THREADS}-1) > \
        analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.no_unmapped_reads.sorted.bam

    # Delete the uncompressed sam file
    rm analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.sam
    #==============================================================================================#

    #==============================================================================================#
    # Get per-contig read counts
    #==============================================================================================#
        # output format (tab-delimited):
        # contig_name    contig_length    number_mapped_reads    number_unmapped_reads

    # Retrieve the statistics; drop the last column b/c it's uninformative; and get rid of the last
    # line because it's just unmapped reads, which we already have from samtools flagstat
    samtools idxstats \
        --threads $(expr ${NUM_THREADS}-1) \
        analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.no_unmapped_reads.sorted.bam |
    cut -f1,2,3 |
    head -n -1 > \
        analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.no_unmapped_reads.sorted.counts.txt
    #==============================================================================================#

    #==============================================================================================#
    # Save results as a tab-delimited table
    #==============================================================================================#

    #============================================================================================#
    # similar to the taxonomy table, but with per-contig length & read counts as final 2 columns;
    # make sure they are both input files are sorted on the contigs so it merges properly
    #
    # However, the names of the contigs are NODE_####, which is difficult for 'sort' to parse;
    # I cannot get it to sort NODE_1_ before NODE_101_, perhaps b/c of the mixed letters+numbers;
    # So at the end, I will re-sort the table by contig length (longest first) -- the original order
    #
    # The final step is to calculate a normalized coverage value per contig, as such:
    # (number_mapped_reads * read_length) / (contig_length)
    #============================================================================================#

    #==========================================================================================#
    # Temporarily disabling 'set -eo pipefail' protections
    #==========================================================================================#
    # Samtools does not play well with 'head';
    # 'head' sends a SIGPIPE stop pipe signal to Samtools to limit its output to 'n' number of lines;
    # but samtools ignores that, which 'head' does not like, so it does its job but exits with an error 141;
    # So I have to temporarily turn off error protection that normally protects against these kinds of errors
    # It does not appear to impact the results, and it is a somewhat common occurance
    # see a similar report on the official samtools issues website @
    # https://sourceforge.net/p/samtools/mailman/message/33035179/
    #
    set +eo pipefail
    #==========================================================================================#

    # Merge the taxonomy table and the counts reads table; save as a temporary table
    join \
        -t $'\t' \
        <(sort -k1,1n ${taxonomy_table}) \
        <(sort -k1,1n analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.no_unmapped_reads.sorted.counts.txt) | \
        sort -rnk12,12 - > \
        "${mapped_table}.temp"

    # Calculate average read length of mapped reads by looking at first million reads
    average_read_length=$(samtools view \
        analysis/mapping/processing/${SAMPLES}.mapped_reads_to_contigs.no_unmapped_reads.sorted.bam | \
        head -n 1000000 | \
        awk '{ sumOfReadLengths += length($10); numReads++ } END \
             { print int(sumOfReadLengths / numReads) }')

    # Make a header for the final table
    echo -e "Contig_name\t" \
            "Taxon_ID\t" \
            "e-value\t" \
            "Superkingdom\t" \
            "Kingdom\t" \
            "Phylum\t" \
            "Class\t" \
            "Order\t" \
            "Family\t" \
            "Genus\t" \
            "Species\t" \
            "Contig_length\t" \
            "Mapped_reads\t" \
            "Coverage_value" > ${mapped_table}

    # Determine the per-contig coverage values, and
    # append this as the final column on the permanent final mapped table
    awk \
        -v avg_read_len="${average_read_length}" \
        '{ print $0"\t"(($13 * avg_read_len)/$12) }' \
        "${mapped_table}.temp" >> \
        ${mapped_table}

    # Remove temporary file
    rm "${mapped_table}.temp"

    # Re-enable error-checking protection
    set -eo pipefail
    #==============================================================================================#

    #==============================================================================================#
    # Logging info for the mapping stage
    #==============================================================================================#
    # Note on the coverage value calculation
    echo -e "Note on the 'coverage_value' determination in the final mapped table: \n" \
            "Coverage values were calculated as such: \n\n" \
            "    (number_mapped_reads * read_length) / contig_length \n\n" \
            "This value reflects the average coverage per nucleotide across the contig. \n" |
            tee -a analysis/timelogs/${SAMPLES}.log

    # Log completion time
    echo -e "Finished mapping stage at: \n" \
            "$(date)" | tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#

}

function extract_viral() {
    #==============================================================================================#
    # This function will extract the viral sequences, save their taxonomy info to
    # a tab-delimited text file, and then save the sequences in a FASTA file
    #==============================================================================================#

    #==============================================================================================#
    # Error checking
    #==============================================================================================#
    # Make sure that seqtk is installed
    command -v seqtk > /dev/null || \
    {   echo -e "ERROR: This script requires the tool 'seqtk' but could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6
        }

    # Check to make sure there is a DIAMOND results file to read from
    if [[ ! -f analysis/diamond/${SAMPLES}.nr.diamond.txt ]] ;
    then echo -e "ERROR: No DIAMOND results file found. \n" \
                 "Exiting with error code 7 ..." >&2; exit 7
    fi
    #==============================================================================================#

    #==============================================================================================#
    # Viral sequences log info
    #==============================================================================================#
    echo "Beginning extraction of viral sequences at:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#

    #==============================================================================================#
    # Extract viral sequences and save them to a new file
    #==============================================================================================#
    # Save the virus-specific taxonomy results
    grep Viruses analysis/taxonomy/${SAMPLES}.nr.diamond.taxonomy.txt > \
         analysis/viruses/${SAMPLES}.viruses.taxonomy.txt

    # Retrieve the viral sequences and save them in a FASTA file
    grep Viruses analysis/taxonomy/${SAMPLES}.nr.diamond.taxonomy.txt | \
    cut -f 1 | \
    seqtk subseq analysis/contigs/${SAMPLES}.contigs.fasta - > \
          analysis/viruses/${SAMPLES}.viruses.fasta
    #==============================================================================================#

    #==============================================================================================#
    # Print number of viral sequences
    #==============================================================================================#
    echo "Number of viral contigs in ${SAMPLES}:"
    grep "^>" analysis/viruses/${SAMPLES}.viruses.fasta | \
    wc -l
    #==============================================================================================#

    #==============================================================================================#
    # Viral sequences log info
    #==============================================================================================#
    echo "Finished extraction of viral sequences at:    $(date)" | \
        tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#
}

function cleanup() {
    #==============================================================================================#
    # This is a final cleanup function that will save files to a final, permanent
    # location and delete all the temporary files
    #==============================================================================================#

    #==============================================================================================#
    # Copy results to final, permanent directory
    #==============================================================================================#
    # Make necessary subdirectories in final directory
    mkdir -p ${FINAL_DIR}/analysis
    mkdir -p ${FINAL_DIR}/scripts

    # Copy most of the analysis files
    rsync -azv ${WORKING_DIR}/analysis/contigs/${SAMPLES}* ${FINAL_DIR}/analysis/contigs/
    rsync -azv ${WORKING_DIR}/analysis/diamond/${SAMPLES}* ${FINAL_DIR}/analysis/diamond/
    rsync -azv ${WORKING_DIR}/analysis/taxonomy/${SAMPLES}* ${FINAL_DIR}/analysis/taxonomy/
    rsync -azv ${WORKING_DIR}/analysis/timelogs/${SAMPLES}* ${FINAL_DIR}/analysis/timelogs/
    rsync -azv ${WORKING_DIR}/analysis/viruses/${SAMPLES}* ${FINAL_DIR}/analysis/viruses/

    # Copy the mapping files (a little more complicated so they get their own block)
    rsync -azv --no-r ${WORKING_DIR}/analysis/mapping/${SAMPLES}* \
                      ${FINAL_DIR}/analysis/mapping/
    rsync -azv --no-r ${WORKING_DIR}/analysis/mapping/processing/${SAMPLES}*sorted.bam \
                      ${FINAL_DIR}/analysis/mapping/processing/
    rsync -azv --no-r ${WORKING_DIR}/analysis/mapping/processing/${SAMPLES}*sorted.counts.txt \
                      ${FINAL_DIR}/analysis/mapping/processing/
    rsync -azv --no-r ${WORKING_DIR}/analysis/mapping/processing/${SAMPLES}*stats \
                      ${FINAL_DIR}/analysis/mapping/processing/

    # Copy the scripts
    rsync -azv --no-r ${WORKING_DIR}/scripts/ ${FINAL_DIR}/scripts/

    # If DIAMOND database files had to be downloaded, copy those to a permanent directory too
    if [[ ! -z "${NEW_DIAMOND_DB}" ]]; then
        echo -e "Copying DIAMOND database & taxonomy files to permanent storage at ${FINAL_DIR}/scripts/diamond_db \n" \
                "Next time you run dnatax, you may use these files with the flag '-d ${FINAL_DIR}/scripts/diamond_db/nr'"
        mkdir -p ${FINAL_DIR}/scripts/diamond_db/
        rsync -azv ${TEMP_DIR}/diamond_db/ ${FINAL_DIR}/scripts/diamond_db
    fi
    #==============================================================================================#

    #==============================================================================================#
    # Handle FASTQ files
    mkdir -p ${FINAL_DIR}/data/raw-sra
    mkdir -p ${FINAL_DIR}/data/fastq-adapter-trimmed

    echo "FASTQ files not saved long-term; " \
         "may be available in the working directory if needed: ${WORKING_DIR}" > \
         ${FINAL_DIR}/data/raw-sra/README.txt

    echo "FASTQ files not saved long-term; " \
         "may be available in the working directory if needed: ${WORKING_DIR}" > \
         ${FINAL_DIR}/data/fastq-adapter-trimmed/README.txt
    #==============================================================================================#

    #==============================================================================================#
    # Remove temporary files
    rm -R ${TEMP_DIR}
    #==============================================================================================#

    #==============================================================================================#
    # Tell user that the pipeline has finished successfully and where to find the final files
    echo -e "dnatax pipeline finished successfully at $(date) \n" \
            "Final files are located at ${FINAL_DIR} \n\n" \
            "Have a fantastic day!" | \
    tee -a analysis/timelogs/${SAMPLES}.log
    #==============================================================================================#
}

#==================================================================================================#
# Run the pipeline
#==================================================================================================#
download_sra
determine_library_type
adapter_trimming
de_novo_assembly
classification
taxonomy
mapping
extract_viral
cleanup
#==================================================================================================#

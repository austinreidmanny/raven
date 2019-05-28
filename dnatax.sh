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

# Stop program if it any component fails
set -eo pipefail

function usage() {
    #==== FUNCTION ================================================================================#
    #        NAME: usage
    # DESCRIPTION: setup a usage statement that will inform the user how to correctly invoke the
    #              program
    #==============================================================================================#

    echo -e "\nERROR: Missing project and/or sample names. \n" \
            "Make sure to provide a project name, \n" \
            "one (or more) SRA run numbers separated by commas \n\n" \
            "Usage: $0 -p PROJECT -s SRR10001,SRR10002,SRR..." \
            "Optional parameters: \n" \
                  "-l (library type of the reads; 'paired' or 'single'; [default=auto determine]) \n" \
                  "-m (maximum amount of memory to use [in GB]; [default=16] ) \n" \
            "Example of a complex run: \n" \
            "$0 -p trichomonas -s SRR1001,SRR10002 -l paired -m 30\n\n" \
            "Exiting program. Please retry with corrected parameters..." >&2; exit 1;
}

#==================================================================================================#
# Make sure the pipeline is invoked correctly, with project and sample names
#==================================================================================================#
    while getopts "p:s:l:m:" arg;
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
                    PAIRED=1; SINGLE=0;
                  elif [[ ${LIB_TYPE} == "single" ]]; then
                    PAIRED=0; SINGLE=1
                  else
                    echo "ERROR: Library type must be 'paired' or 'single'. Exiting" >&2
                    exit 3;
                  fi;
                        ;;

                m ) # set max memory to use (in GB; if any letters are entered, discard those)
                    MEMORY_ENTERED=${OPTARG}
                    MEMORY_TO_USE=$(echo $MEMORY_ENTERED | sed 's/[^0-9]*//g')
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

    # Retrieve name of the last sample (uses  older but cross-platform compatible BASH notation)
    LAST_SAMPLE=${ALL_SAMPLES[${#ALL_SAMPLES[@]}-1]}

    # Create a variable that other parts of this pipeline can use mostly for naming
    SAMPLES="${ALL_SAMPLES[0]}-${LAST_SAMPLE}"

    # Reset global expansion [had to change to read multiple sample names]
    set +f

    #==============================================================================================#
    # Set up number of CPUs to use and RAM
    #==============================================================================================#
    # CPUs (aka threads aka processors aka cores):
    #   If 8 CPUs were used, BLAST fails & gives Segmentation Fault. Error stopped if <= 4 CPUs are used
    #   Strategy: Use up to 4 CPUs, or maximum available if less than 4 CPUs available

    # Use `nproc` if installed (Linux or MacOS with gnu-core-utils); otherwise use `systctl`
    { \
        command -v nproc > /dev/null && \
        NUM_THREADS=`nproc` && \
        echo "Number of processors available (according to nproc): ${NUM_THREADS}"; \
    } || \
    { \
        command -v sysctl > /dev/null && \
        NUM_THREADS=`sysctl -n hw.ncpu` && \
        echo "Number of processors available (according to sysctl): ${NUM_THREADS}";
    }
    #==============================================================================================#
    # Set memory usage to 16GB if none given by user
    if [[ -z ${MEMORY_TO_USE} ]]; then
        echo "No memory limit set by user. Defaulting to 16GB"
        MEMORY_TO_USE="16"
    fi

    # As a check to the user, print the project name and sample numbers to the screen
    echo "PROJECT name: ${PROJECT}"
    echo "SRA sample accessions: ${SAMPLES}"
#==================================================================================================#

#==================================================================================================#
# Set up project directory structure
#==================================================================================================#

    #   project-name/
    #     |_ data/
    #     |_ analysis/
    #     |_ scripts/

    # Will run all the analysis in scratch space (maximum read/write speed)
    # Will allocate specific temp space that is deleted at end of job
    # Will save final results in a permanent space

    # Customize the paths for Home, Working, Temp, and Final directories #
    #==============================================================================================#
    export HOME_DIR=`pwd`
    export WORKING_DIR="/n/scratch2/am704/nibert/${PROJECT}/"
    export TEMP_DIR="/n/scratch2/am704/tmp/${PROJECT}/${SAMPLES}/"
    export FINAL_DIR="/n/data1/hms/mbib/nibert/austin/${PROJECT}/"
    export DIAMOND_DB_DIR="/n/data1/hms/mbib/nibert/austin/diamond/nr"
    #==============================================================================================#

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

    # Copy key taxonomy script from HOME to WORKING dir
    if [[ -f ${HOME_DIR}/diamondToTaxonomy.py ]]
      then echo "All neccessary scripts are available to copy. COPYING...";
      cp ${HOME_DIR}/diamondToTaxonomy.py scripts/

    # If the scripts are not available to copy, then tell user where to download
    # them, then exit
    else
      echo -e "One or more of the following scripts are missing: \n" \
              "diamondToTaxonomy.py" >&2
      echo "Please download this from github.com/austinreidmanny/dnatax" >&2
      echo "ERROR: Cannot find mandatory helper scripts. Exiting" >&2
      exit 1
    fi

    # Setup script has finished
    echo "Setup complete"
#==================================================================================================#

function download_sra() {
    ################################################################################################
    # Downloads the transcriptomes from the NCBI Sequence Read Archive (SRA)
    ################################################################################################

    ################################################################################################
    # Ensure that the necessary software is installed
    command -v fasterq-dump >&2 || \
    {
    echo -e "ERROR: This script requires 'fasterq-dump' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2 && exit 6
    }
    ################################################################################################

    ################################################################################################
    # Add the download from SRA step to the timelog file
    echo "Downloading input FASTQs from the SRA at:" > \
    analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log

    # Disable error checking because fasterq-dump treats 'existing files' as a failure
    set +eo pipefail
    ################################################################################################

    ################################################################################################
    # Download fastq files from the SRA
    for SAMPLE in ${SAMPLES}
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
    ################################################################################################

    # Reset the error checking
    set -eo pipefail

    # If no library type is given by user, determine if single reads or paired-end reads by looking
    # at file naming scheme; SRA & fasterq-dump give specific naming scheme for paired vs. unpaired
    if [[ -z ${PAIRED} ]] || [[ -z ${SINGLE} ]] ; then
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
   fi

   echo "finished downloading SRA files"
}

function adapter_trimming() {
    ################################################################################################
    # Trim adapters from raw SRA files
    ################################################################################################

    ################################################################################################
    # Load necessary software packages
    module load gcc/6.2.0 >&2
    module load python/2.7.12 >&2
    module load trimgalore >&2

    ################################################################################################

    ################################################################################################
    # Ensure that the necessary software is installed
    command -v python2 || \
    echo -e "ERROR: This script requires 'python2' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6

    command -v trim_galore || \
    echo -e "ERROR: This script requires 'trim_galore' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6
    ################################################################################################

    ################################################################################################
    # Adapter trimming log info
    echo "Began adapter trimming at" >> analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log
    ################################################################################################

    ################################################################################################
    # Run TrimGalore! in paired or single end mode, depending on input library type

    ## Paired-end mode
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

    ## Single/unpaired-end mode
    elif [[ ${SINGLE} > 0 ]] && \
         [[ ${PAIRED} = 0 ]]
         then for SAMPLE in ${ALL_SAMPLES}
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
    ################################################################################

    ################################################################################
    # Adapter trimming log info
    echo "Finished adapter trimming at" >> analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log
    ################################################################################
}

function de_novo_assembly() {
    ################################################################################################
    # This function will assemble long contiguous sequences (contigs) from the raw
    # raw reads from the FASTQ. These contigs will be much longer than the raw reads
    # and will more accurately reflect the input nucleic acids
    ################################################################################################

    ################################################################################################
    # Load necessary software from the cluster; if not on the cluster, ensure that
    # python3 is available to call (i.e. in your PATH)
    module load gcc/6.2.0 1>&2
    module load python/3.6.0 1>&2
    ################################################################################################

    ################################################################################################
    # Error checking
    ################################################################################################

    # Make sure that rnaSPAdes is installed
    command -v rnaspades.py || \
    echo -e "ERROR: This script requires 'rnaspades' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6

    # Make sure that python3 is installed
    command -v python3 || \
    echo -e "ERROR: This script requires 'python3' but it could not found. \n" \
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
       then yaml_spades_pairedreads ${ALL_SAMPLES}
    elif [[ ${SINGLE} > 0 ]] && \
         [[ ${PAIRED} = 0 ]]
       then yaml_spades_singlereads ${ALL_SAMPLES}
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
    --threads ${NUM_THREADS} \
    -m ${MEMORY_TO_USE} \
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
}

function yaml_spades_singlereads() {
    YAML_OUTPUT="scripts/${SAMPLES}.input.yaml"
    FILES=${@}

    # Write beginning of the file
    echo '    [
          {
            type: "single",
            single reads: [' > ${YAML_OUTPUT}

    # For each SRX, write the location of the forward reads
    for SAMPLE in ${FILES}
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
    YAML_OUTPUT="scripts/${SAMPLES}.input.yaml"
    FILES=${@}

    # Write beginning of the file
    echo '    [
          {
            orientation: "fr",
            type: "paired-end",
            left reads: [' > ${YAML_OUTPUT}

    # For each SRX, write the location of the forward reads
    for SAMPLE in ${FILES}
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
    for SAMPLE in ${FILES}
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
    # Make sure that DIAMOND is installed
    command -v diamond || \
    echo -e "ERROR: This script requires 'diamond' but it could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6

    # Check for a DIAMOND database to use
    if [[ -z "${DIAMOND_DB_DIR}" ]] ; then
        echo -e "ERROR: Missing directory for Diamond database. \n" \
                "Please specify this DIAMOND_DB_DIR value in the setup function" >&2
        exit 4
    fi
    ################################################################################

    ################################################################################
    # DIAMOND log start
    ################################################################################
    echo "Began taxonomic classification at:" >> analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log
    ################################################################################

    ################################################################################
    # Classify the contigs with Diamond
    ################################################################################
    # (Parameters 'block-size' and 'index-chunks' optimized for 50GB memory)

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
    --block-size 5 \
    --index-chunks 2 \
    --tmpdir ${TEMP_DIR}
    ################################################################################

    ################################################################################
    # DIAMOND log end
    echo "Finished taxonomic classification:" >> analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log
    ################################################################################
}

function taxonomy() {

    ################################################################################
    # Check to make sure the diamondToTaxonomy.py script is available
    if [[ ! -f scripts/diamondToTaxonomy.py ]] ;
      then echo -e "ERROR: No diamondToTaxonomy.py script found. \nExiting..." >&2
      exit 5
    fi
    ################################################################################

    ################################################################################
    # Taxonomy log info
    ################################################################################
    echo "Beginning taxonomy conversion:" >> analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log
    ################################################################################

    ################################################################################
    # Convert taxon IDs to full taxonomy strings
    ################################################################################
    cd analysis/diamond/
    ../../scripts/diamondToTaxonomy.py ${SAMPLES}.nr.diamond.txt
    mv ${SAMPLES}.nr.diamond.taxonomy.txt ../taxonomy/
    cd ../../
    ################################################################################

    ################################################################################
    # Taxonomy sequences log info
    ################################################################################
    echo "Finished taxonomy conversion:" >> analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log
    ################################################################################
}

function extract_viral() {
    ################################################################################
    # This function will extract the viral sequences, save their taxonomy info to
    # a tab-delimited text file, and then save the sequences in a FASTA file
    ################################################################################

    ###############################################################################
    # Error checking
    ###############################################################################
    # Make sure that seqtk is installed
    command -v seqtk || \
    echo -e "ERROR: This script requires the tool 'seqtk' but could not found. \n" \
            "Please install this application. \n" \
            "Exiting with error code 6..." >&2; exit 6

    # Check to make sure sample names are given
    if [[ -z "${SAMPLES}" ]] ;
      then echo -e "ERROR: Missing Sample names.\n Exiting with error code 1" >&2
      exit 1
    fi

    # Check to make sure there is a DIAMOND results file to read from
    if [[ ! -f analysis/diamond/${SAMPLES}.nr.diamond.txt ]] ;
    then echo -e "ERROR: No DIAMOND results file found. \n" \
                 "Exiting with error code 7 ..." >&2; exit 7
    fi
    ###############################################################################

    ################################################################################
    # Viral sequences log info
    ################################################################################
    echo "Beginning extraction of viral sequences at:" >> \
         analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log
    ################################################################################

    ################################################################################
    # Extract viral sequences and save them to a new file
    ################################################################################
    # Save the virus-specific taxonomy results
    grep Viruses analysis/taxonomy/${SAMPLES}.nr.diamond.taxonomy.txt > \
         analysis/viruses/${SAMPLES}.viruses.taxonomy.txt

    # Retrieve the viral sequences and save them in a FASTA file
    grep Viruses analysis/taxonomy/${SAMPLES}.nr.diamond.taxonomy.txt | \
    cut -f 1 | \
    seqtk subseq data/contigs/${SAMPLES}.contigs.fasta - > \
          analysis/viruses/${SAMPLES}.viruses.fasta
    ################################################################################

    ################################################################################
    # Print number of viral sequences
    ################################################################################
    echo "Number of viral contigs in ${SAMPLES}:"
    grep "^>" analysis/viruses/${SAMPLES}.viruses.fasta | \
    wc -l
    ################################################################################

    ################################################################################
    # Viral sequences log info
    ################################################################################
    echo "Finished extraction of viral sequences at:" >> \
         analysis/timelogs/${SAMPLES}.log
    date >> analysis/timelogs/${SAMPLES}.log
    ################################################################################

}

function cleanup() {
    ################################################################################
    # This is a final cleanup function that will save files to a final, permanent
    # location and delete all the temporary files
    ################################################################################

    ################################################################################
    # Error checking
    ################################################################################
    # If any step fails, the function will stop to prevent propogating errors
    set -euo pipefail
    ################################################################################

    ################################################################################
    # Copy results to final, permanent directory
    ################################################################################
    mkdir -p ${FINAL_DIR}/analysis
    mkdir -p ${FINAL_DIR}/scripts
    mkdir -p ${FINAL_DIR}/data/contigs/

    rsync -azv ${WORKING_DIR}/analysis/ ${FINAL_DIR}/analysis
    rsync -azv ${WORKING_DIR}/scripts/ ${FINAL_DIR}/scripts
    rsync -azv ${WORKING_DIR}/data/contigs/ ${FINAL_DIR}/data/contigs
    ################################################################################

    ################################################################################
    # Handle FASTQ files
    mkdir -p ${FINAL_DIR}/data/raw-sra
    mkdir -p ${FINAL_DIR}/data/fastq-adapter-trimmed

    echo "FASTQ files not saved long-term; " \
         "may be available in the working directory if needed: ${WORKING_DIR}" > \
         ${FINAL_DIR}/data/raw-sra/README.txt

    echo "FASTQ files not saved long-term; " \
         "may be available in the working directory if needed: ${WORKING_DIR}" > \
         ${FINAL_DIR}/data/fastq-adapter-trimmed/README.txt
    ################################################################################

    ################################################################################
    # Remove temporary files
    rm -R ${TEMP_DIR}
    ################################################################################
}

#==================================================================================================#
# Run the pipeline
#==================================================================================================#
download_sra
adapter_trimming
de_novo_assembly
classification
taxonomy
extract_viral
cleanup
#==================================================================================================#

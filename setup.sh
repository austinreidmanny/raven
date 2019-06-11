#!/bin/bash

#==============================================================================#
# DNAtax setup
#==============================================================================#
# Objective: The purpose of this script is to set up the computational         #
#            environment in a reproducibile and robust way. As DNAtax relies   #
#            upon a multitude of software from various authors and channels,   #
#            any discrepancies can lead to software breaking or giving         #
#            conflicting results. This setup.sh script aims to prevent that.   #
#==============================================================================#

function install_conda() {

    # Tell user that you are installing conda, then download and install it
    echo -e "\nDNAtax uses the program 'conda' in order to make sure all the necessary " \
    "software is installed and up to date. \n\n" \
    "Please confirm all of the following prompts... \n\n"

    if [[ "${OSTYPE}" == "linux-gnu" ]]; then
        wget -O - https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh > \
          Miniconda3-latest-Linux-x86_64.sh
        bash Miniconda3-latest-Linux-x86_64.sh

    elif [[ "${OSTYPE}" == "darwin"* ]]; then
        curl -s -o Miniconda3-latest-MacOSX-x86_64.sh \
          https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh
        bash Miniconda3-latest-MacOSX-x86_64.sh
    fi

    # Conda is now installed, but the shell needs to start in order to run it
    # Alert the user to rerun the script
    echo -e "\n\n ATTENTION: To complete installation, please rerun this script. \n" \
            "This will allow the system to update and enable you to use the software. Please rerun. \n\n"

    # Launch a new subshell (which will load conda); when user relaunches the script, it will
    # continue to the setup_dnatax function and finish setup
    exec bash -l
    }

function setup_dnatax() {
    # Test to make sure that conda is installed correctly
    conda list > /dev/null || \
    {  echo "Conda was not set up correctly. Please retry or manually install Miniconda."
       exit 1
    }

    # Configure conda to include the bioinformatics channels
    conda config --add channels defaults
    conda config --add channels bioconda
    conda config --add channels conda-forge

    # Setup a new environment where all the software needed for dnatax will be installed
    conda create --name env_dnatax \
    seqtk=1.3 sra-tools=2.9.1_1 spades=3.13.1 diamond=0.9.21 trim-galore=0.6.2 wget

    # Tell the user that the setup has completed!
    echo -e "All necessary software as been successfully installed! \n" \
            "The DNAtax pipeline is now ready to run."
    exit 0
    }

# If the conda package manager is installed, run the setup; otherwise, install conda first
conda -V 2&> /dev/null || install_conda
setup_dnatax

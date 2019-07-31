# dnatax
De Novo Assembly & TAXonomic classfication

## Objective
`dnatax` is a virus discovery pipeline for finding viruses in publicly available transcriptome data.

This pipeline simply takes in one or more SRA accession number (for RNA-seq datasets in the NCBI Sequence Read Archive)
and returns a list of viruses and their sequences.

The steps are:
- Download reads [NCBI sra-tools]
- Adapter trimming [TrimGalore]
- Contig assembly [rnaSPAdes]
- Taxonomic classification [diamond]
- Translate taxonomy [custom scripts using JGI-ISF]
- Binning [custom code to parse taxonomy results > seqtk]
- Print results to user

## Usage
```
Usage: ./dnatax.sh -p PROJECT -s SRR10001,SRR10002,SRR... 

Optional parameters: 
 -l (library type of the reads; 'paired' or 'single'; [default=auto determine]) 
 -m (maximum amount of memory to use [in GB]; [default=16] ) 
 -n (maximum number of CPUs to use; [default=attempt to auto-determine; not perfect]) 
 -w (set the working directory, where all analysis will take place; [default=current directory, 
 but a scratch directory with a lot of storage is recommended]) 
 -f (set the final directory, where all the files will be copied to the end [default=current directory]) 
 -t (set the temporary directory, where the pipeline will dump all temp files [default='/tmp/dnatax/'] 
 -h (set the home directory where DNAtax is located; [default=current directory, is recommended not to change]) 
 -d (specify the full path to the DIAMOND database, including the db name - e.g., '/path/to/nr-database/nr' 
 [default=none, will download all files to temp space and copy them to final directory at the end; NOTE: 
 DNAtax requires a DIAMOND database, NCBI taxonmaps file, and NCBI protein2accessions file; 
 These all must be located in the same directory as the DIAMOND database 

 Example of a complex run: 
 ./dnatax.sh -p trichomonas -s SRR1001,SRR10002 -l paired -m 30 -w external_drive/storage/ -f projects/dnatax/final/ -t /tmp/ -d tools/diamond/nr 
```

## Limitations and desired changes
* Add a mapping step. This would take the adapter-trimmed reads and map them to the de novo assembled contigs, and then divide number of mapped reads by length of contig in order to generate coverage values. 
* I would also like to implement a filtering step for contigs, that discards any contigs <300 nt. That should speed up the classification step, improve mapping, and be provide less noise/useless info to the user.
*  As it stands, this pipeline only works with RNA-seq data. The de novo assembly step invokes rnaSPAdes. That is really the only RNA-depndent portion of the pipeline. I could add an rna/dna option to the list of parameters and alter the assembly step to make it more flexible (like I did with `de_novo_assembly.sh` @ github.com/austinreidmanny/nibert-lab-tools`)


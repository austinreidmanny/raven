#!/bin/bash

OUTPUT="scripts/${SAMPLES}.input.yaml"
FILES=${@}

# Write beginning of the file
echo '    [
      {
        type: "single",
        single reads: [' > ${OUTPUT}

# For each SRX, write the location of the forward reads
for SAMPLE in ${FILES}
   do
      echo -n \
      '          "../data/fastq-adapter-trimmed/' >> ${OUTPUT}
      echo \
      ${SAMPLE}_trimmed.fq\", >> ${OUTPUT}
   done
   
# Remove the last comma
sed '$ s/.$//' ${OUTPUT} > ${OUTPUT}.temp
mv ${OUTPUT}.temp ${OUTPUT}

# Write the last bit of formatting
echo \
'        ]
      },
     ]' >> ${OUTPUT}

# Completion
echo "Finished contructing single-read input yaml for ${SAMPLES}"

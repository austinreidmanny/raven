#!/bin/bash

OUTPUT="./${SAMPLES}.input.yaml"
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
      '          "/n/scratch2/am704/nibert/' >> ${OUTPUT}
      echo \
      ${PROJECT}/sra/${SAMPLE}.fastq\", >> ${OUTPUT}
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
echo "Finished contructing single-read input yaml for ${1}-${!#}"

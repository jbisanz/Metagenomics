#!/bin/bash
#$ -S /bin/bash
#$ -o concoct.log
#$ -e concoct.error
#$ -cwd
#$ -r y
#$ -j y
#$ -l mem_free=16G
#$ -l arch=linux-x64
#$ -l scratch=50G
#$ -l h_rt=336:0:0
#$ -pe smp 6
#$ -t 1-53

#requirements:
#a list of samples is stored in a text file called jobs.txt with one sample name per line, the last number on line 13 is the number of lines in this file
#example: head -n 2 jobs.txt:
#QiYan_Ang_OB006_B2_S98
#QiYan_Ang_OB008_B4_S100
#...

#a folder called reads with the appropriate paired end reads, in this case from the biohub NovaSeq:
#example: ls -1 reads/ | head -n 4
#QiYan_Ang_OB006_B2_S98_R1_001.fastq.gz
#QiYan_Ang_OB006_B2_S98_R2_001.fastq.gz
#QiYan_Ang_OB008_B4_S100_R1_001.fastq.gz
#QiYan_Ang_OB008_B4_S100_R2_001.fastq.gz

source activate metawrap-env
#version 1.0

#/turnbaugh/qb3share/shared_resources/qiime2/envs/metawrap-env/bin/config-metawrap -> see for database configs


SAMPLE=$( sed "${SGE_TASK_ID}q;d" jobs.txt)

echo $SGE_TASK_ID running $SAMPLE on $(hostname) at $(date)

exec >/turnbaugh/qb3share/jbisanz/IDEO_metawrap/logs/${SAMPLE}_${JOB_ID}_${SGE_TASK_ID}.log 2>/turnbaugh/qb3share/jbisanz/IDEO_metawrap/logs/${SAMPLE}_${JOB_ID}_${SGE_TASK_ID}.err

mkdir /scratch/${SAMPLE}_${JOB_ID}
cp reads/${SAMPLE}* /scratch/${SAMPLE}_${JOB_ID}
cd /scratch/${SAMPLE}_${JOB_ID}
mv ${SAMPLE}_R1_001.fastq.gz ${SAMPLE}_1.fastq.gz #need this name format or will throw error in pipeline
mv ${SAMPLE}_R2_001.fastq.gz ${SAMPLE}_2.fastq.gz
pigz -d *fastq.gz

echo $(date) Step 1 ...... Read_QC read trimming and human read removal
    metawrap read_qc \
    -1 ${SAMPLE}_1.fastq \
    -2 ${SAMPLE}_2.fastq  \
    -o z1_read_qc \
    -t $NSLOTS
    
echo $(date) Step 2 ...... Assembly  and qc with MegaHit
    metawrap assembly \
    -1 z1_read_qc/final_pure_reads_1.fastq \
    -2 z1_read_qc/final_pure_reads_2.fastq \
    -o z2_assembly \
    -m 96 \
    -t $NSLOTS

echo $(date) Step 3 ...... Binning with MaxBin2, metaBAT2, and CONCOCT
    metawrap binning \
    -o z3_binning \
    -a z2_assembly/final_assembly.fasta \
    -t $NSLOTS \
    -m 96 \
    --metabat2 \
    --maxbin2 \
    --concoct \
    z1_read_qc/final_pure_reads_1.fastq \
    z1_read_qc/final_pure_reads_2.fastq

echo $(date) Step 4 ...... Bin_refinement: consolidate of multiple binning predicitons into a superior bin set
    metawrap bin_refinement \
    -o z4_bin_refinement \
    -t $NSLOTS \
    -m 96 \
    -A z3_binning/concoct_bins \
    -B z3_binning/maxbin2_bins \
    -C z3_binning/metabat2_bins \
    -c 50 \
    -x 10


echo $(date) Step 5 ...... Reassemble_bins: reassemble bins to improve completion and N50, and reduce contamination
    metawrap reassemble_bins \
    -b  z4_bin_refinement/metaWRAP_bins \
    -o z5_reassemble_bins \
    -t $NSLOTS \
    -m 96 \
    -c 50 \
    -x 10 \
    -1 z1_read_qc/final_pure_reads_1.fastq \
    -2 z1_read_qc/final_pure_reads_2.fastq

echo $(date) Step 6 ...... Classify_bins: conservative but accurate taxonomy prediction for bins
    metawrap classify_bins \
    -o z6_classify_bins \
    -t $NSLOTS \
    -b z5_reassemble_bins/reassembled_bins

    
echo $(date) Step 7 ...... Annotate_bins: functionally annotate genes in a set of bins
    metawrap annotate_bins \
    -o z7_annotate_bins \
    -t $NSLOTS \
    -b z5_reassemble_bins/reassembled_bins

echo $(date) Cleaning up ...... removing/decompressing intermediate fastqs

rm ${SAMPLE}_1.fastq
rm ${SAMPLE}_2.fastq

for f in $( find . -type f -name "*.fastq" ); do
	echo compressing .... $f
	pigz $f
done

echo $(date) Moving files to perminant storage....

cp  -r /scratch/${SAMPLE}_${JOB_ID} /turnbaugh/qb3share/jbisanz/IDEO_metawrap/bins/${SAMPLE}
rm -r /scratch/${SAMPLE}_${JOB_ID}

echo $(date) Complete

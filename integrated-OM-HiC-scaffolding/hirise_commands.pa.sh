
#############################
#
#specify the input files:
#


BAMS=($1)
INPUT_FASTA=$2
SHOTGUN_BAM=$3

#
#############################

#### 
#
#Some of the scripts expect comma-separated lists of bam files, others expect repeated command-line flags.  
#
BAM1=${BAMS[0]}
echo $BAM1

BAMLIST_OPT=""
for f in ${BAMS[@]}
do
BAMLIST_OPT+="-b $f "
done
echo $BAMLIST_OPT


BAMLIST_COMMA=$BAM1
unset BAMS[0]
for f in ${BAMS[@]}
do
BAMLIST_COMMA+=",$f"
done
echo $BAMLIST_COMMA
BAMS+=($BAM1)
echo ${BAMS[*]}

HISTOGRAMS=""
#unset BAMS[0]
for f in ${BAMS[@]}
do
HISTOGRAMS+=`basename $f` 
HISTOGRAMS+=".histogram "
done
echo "histograms: " $HISTOGRAMS

#
#####

qual1=$4
qual2=$5

##
## HiRise Commands start here:
##
mkdir links
mkdir merge_links
mkdir merge_links_tmp

bam2len.py -b $BAM1 > raw_lengths.txt
if [ ! -e raw_chunks ] ; then mkdir raw_chunks ; fi ; nseqs=`wc -l raw_lengths.txt | cut -d' '  -f 1 ` ; cat raw_lengths.txt | awk '{print $1,0,$2, rand()}'  | sort -k4n | awk '{print $1,$2,$3}' | split -d -l `expr $nseqs / 16 + 1` - raw_chunks/bed_chunk.

samtools mpileup -q $qual1 -l raw_chunks/bed_chunk.00 $SHOTGUN_BAM  | cut -f 1,2,4 | depth_histogram.py -o raw_chunks/00.dhist -t raw_chunks/00.depth_thresholds

if [ ! -e raw_chunks ] ; then mkdir raw_chunks ; fi ; nseqs=`wc -l raw_lengths.txt | cut -d' '  -f 1 ` ; cat raw_lengths.txt | awk '{print $1, rand()}'  | sort -k2n | awk '{print $1}' | split -d -l `expr $nseqs / 16 + 1` - raw_chunks/chunk.

hirise_assembly.py  -o assembly0.hra $BAMLIST_OPT -S $SHOTGUN_BAM
for f in ${BAMS[@]}
do
pair_sep_histogram.py -q $qual2 -b $f > `basename $f`.histogram 2> `basename $f`.histogram.err 
done
add_hist.py $HISTOGRAMS > all.merged_histogram
window_stats.py -i assembly0.hra -N 1000 > contig_window_sample.txt

for k in {0..15};do
 {
  if [ $k -lt 10 ]
  then 
    samtools mpileup -q $qual1 -l raw_chunks/bed_chunk.0$k $SHOTGUN_BAM | cut -f 1,2,4 | dt2.py -t raw_chunks/00.depth_thresholds > raw_chunks/0$k.deep_regions.bed
  else
    samtools mpileup -q $qual1 -l raw_chunks/bed_chunk.$k $SHOTGUN_BAM | cut -f 1,2,4 | dt2.py -t raw_chunks/00.depth_thresholds > raw_chunks/$k.deep_regions.bed 
  fi
 } &
done
wait

contiguity_correction.py -l raw_lengths.txt > contiguity_correction.txt
cat raw_chunks/*.deep_regions.bed > deep_regions.bed

cat contig_window_sample.txt | cut -f 6 | percentile.py -p 98 > chicago_link_density_threshold.txt
estimate_Pn_bam.py -q $qual2 -b $BAMLIST_COMMA -o nn_estimate.txt -N 200 > nn_estimate.txt.out
cat all.merged_histogram | histo_smooth2.py | apply_contiguity_correction.py -c contiguity_correction.txt > all_smoothed_corrected.merged_histogram
cat all_smoothed_corrected.merged_histogram | model_fit.py -m 1000 -P nn_estimate.txt -o datamodel.out > datamodel.out.out


for k in {0..15};do
 {
  link_density_scan.py --mask deep_regions.bed -q $qual2 -i assembly0.hra -m 2 -w 1000 -C 16 -c $k -o promisc_segs_$k.txt  -M $( cat chicago_link_density_threshold.txt ) 
 } &
done
wait

for k in {0..15};do
 {
  if [ $k -lt 10 ]
  then 
    (cat raw_chunks/chunk.0$k | xargs samtools faidx $INPUT_FASTA ) | gap_lengths.py > raw_chunks/gaps.0$k
  else
    (cat raw_chunks/chunk.$k | xargs samtools faidx $INPUT_FASTA ) | gap_lengths.py > raw_chunks/gaps.$k 
  fi
 } &
done
wait

####combine the masked regions
cat promisc_segs_*.txt > promisc_segs.txt
cat promisc_segs.txt > blacklisted_segments.bed
cat raw_chunks/gaps.00 raw_chunks/gaps.01 raw_chunks/gaps.02 raw_chunks/gaps.03 raw_chunks/gaps.04 raw_chunks/gaps.05 raw_chunks/gaps.06 raw_chunks/gaps.07 raw_chunks/gaps.08 raw_chunks/gaps.09 raw_chunks/gaps.10 raw_chunks/gaps.11 raw_chunks/gaps.12 raw_chunks/gaps.13 raw_chunks/gaps.14 raw_chunks/gaps.15 | cut -f 2-4,6 > gaps.bed
hra_readdeserts.py -q $qual2 -i assembly0.hra -o deserts.bed
cat deep_regions.bed blacklisted_segments.bed gaps.bed deserts.bed > combined_mask.bed


###find the potential miss-assembly, break the input assembly contigs/scaffolds
for k in {0..15};do
 {
  if [ $k -lt 10 ]
  then 
     weakspots.py -c raw_chunks/chunk.0$k -b $BAMLIST_COMMA -q $qual2 -t 150 -M datamodel.out -B 2.0 > raw_chunks/breaks.0$k
  else
    weakspots.py -c raw_chunks/chunk.$k -b $BAMLIST_COMMA -q $qual2 -t 150 -M datamodel.out -B 2.0 > raw_chunks/breaks.$k
  fi
 } &
done
wait

hirise_assembly.py -i assembly0.hra -o assembly1.hra -m combined_mask.bed -M datamodel.out
cat raw_chunks/breaks.00 raw_chunks/breaks.01 raw_chunks/breaks.02 raw_chunks/breaks.03 raw_chunks/breaks.04 raw_chunks/breaks.05 raw_chunks/breaks.06 raw_chunks/breaks.07 raw_chunks/breaks.08 raw_chunks/breaks.09 raw_chunks/breaks.10 raw_chunks/breaks.11 raw_chunks/breaks.12 raw_chunks/breaks.13 raw_chunks/breaks.14 raw_chunks/breaks.15 > raw_breaks.txt; cat raw_breaks.txt | merge_ranges.py -w 300 -t 0.0 > breaks.txt 
break_hra.py -i assembly1.hra -b breaks.txt -o broken.hra



for k in {0..15};do
 {
  if [ $k -lt 10 ]
  then 
    export_links.py -C 16 -c 0$k -i broken.hra -o links/0$k.merged.links -q $qual2
  else
    export_links.py -C 16 -c $k -i broken.hra -o links/$k.merged.links -q $qual2
  fi
 } &
done
wait

bamMeanDepth2.py -b $SHOTGUN_BAM -q 10 > mean_depth.txt

for k in {0..15};do
 {
  if [ $k -lt 10 ]
  then 
     cat links/0$k.merged.links | score_links4.py -M datamodel.out  -p 0.0000001 > links/0$k.merged.score
  else
    cat links/$k.merged.links | score_links4.py -M datamodel.out  -p 0.0000001 > links/$k.merged.score
  fi
 } &
done
wait

cat  mean_depth.txt | doubleDepthFilter.py > double_depth.txt

dump_lengths.py -i broken.hra -o broken_lengths.txt

cat links/00.merged.score links/01.merged.score links/02.merged.score links/03.merged.score links/04.merged.score links/05.merged.score links/06.merged.score links/07.merged.score links/08.merged.score links/09.merged.score links/10.merged.score links/11.merged.score links/12.merged.score links/13.merged.score links/14.merged.score links/15.merged.score | grep -v '^#' > merged.scores
cat broken_lengths.txt  | awk '{print $1,$1}'  | sed -e 's/_/ /' | awk '{print $1,$3}'  | screen_out.py -k double_depth.txt 1 | awk '{print $2}' > double_depth_broken.txt
cat merged.scores | awk '{print $1}' | uniq -c | awk '$1>=7 {print $2}' > cluster_blacklist0.txt
cat cluster_blacklist0.txt double_depth_broken.txt > cluster_blacklist.txt
cat merged.scores  | awk '{print $1,$2,$3-$4}' |clusterpledge.py -L links/00.merged.links -L links/01.merged.links -L links/02.merged.links -L links/03.merged.links -L links/04.merged.links -L links/05.merged.links -L links/06.merged.links -L links/07.merged.links -L links/08.merged.links -L links/09.merged.links -L links/10.merged.links -L links/11.merged.links -L links/12.merged.links -L links/13.merged.links -L links/14.merged.links -L links/15.merged.links --fake -b cluster_blacklist.txt -t 4 > chunking_edges.txt 
if [ ! -e link_chunks ] ; then mkdir link_chunks ; fi ; cat links/00.merged.links links/01.merged.links links/02.merged.links links/03.merged.links links/04.merged.links links/05.merged.links links/06.merged.links links/07.merged.links links/08.merged.links links/09.merged.links links/10.merged.links links/11.merged.links links/12.merged.links links/13.merged.links links/14.merged.links links/15.merged.links | component_chunk_filter.py -c 16 -l broken_lengths.txt -E chunking_edges.txt -t 0 -m 1000 > component_x.txt




for k in {0..15};do
 {
  assembler3.py -l broken_lengths.txt -Z component_x.txt -m 1000 -k link_chunks/intra.$k.links -c 1 --set_insert_size_dist_fit_params datamodel.out > assembler.$k.out
  greedy_chicagoan2.py -t 20.0 -l broken_lengths.txt -Z component_x.txt -m 1000 -c $k -j assembler.$k.out -k link_chunks/intra.$k.links --set_insert_size_dist_fit_params datamodel.out > greedy.$k.out
  local_oo_opt.py -E -l link_chunks/intra.$k.links -i greedy.$k.out  --set_insert_size_dist_fit_params datamodel.out > refined.$k.out.inter
  cat refined.$k.out.inter | p2edges.py > refined.$k.out
 } &
done
wait


cat link_chunks/inter.3-10.links link_chunks/intra.3.links link_chunks/intra.10.links | linker4.py -d -a 3 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-10.out 2> merge_links/links.3-10.out.err

cat link_chunks/inter.6-9.links link_chunks/intra.6.links link_chunks/intra.9.links | linker4.py -d -a 6 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-9.out 2> merge_links/links.6-9.out.err
cat link_chunks/inter.12-13.links link_chunks/intra.12.links link_chunks/intra.13.links | linker4.py -d -a 12 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.12.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.12-13.out 2> merge_links/links.12-13.out.err
cat link_chunks/inter.3-12.links link_chunks/intra.3.links link_chunks/intra.12.links | linker4.py -d -a 3 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-12.out 2> merge_links/links.3-12.out.err
cat link_chunks/inter.7-9.links link_chunks/intra.7.links link_chunks/intra.9.links | linker4.py -d -a 7 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-9.out 2> merge_links/links.7-9.out.err
cat link_chunks/inter.9-10.links link_chunks/intra.9.links link_chunks/intra.10.links | linker4.py -d -a 9 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.9.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.9-10.out 2> merge_links/links.9-10.out.err
cat link_chunks/inter.14-14.links link_chunks/intra.14.links link_chunks/intra.14.links | linker4.py -d -a 14 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.14.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.14-14.out 2> merge_links/links.14-14.out.err
cat link_chunks/inter.4-11.links link_chunks/intra.4.links link_chunks/intra.11.links | linker4.py -d -a 4 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-11.out 2> merge_links/links.4-11.out.err
cat link_chunks/inter.12-12.links link_chunks/intra.12.links link_chunks/intra.12.links | linker4.py -d -a 12 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.12.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.12-12.out 2> merge_links/links.12-12.out.err
cat link_chunks/inter.8-15.links link_chunks/intra.8.links link_chunks/intra.15.links | linker4.py -d -a 8 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.8.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.8-15.out 2> merge_links/links.8-15.out.err
cat link_chunks/inter.4-15.links link_chunks/intra.4.links link_chunks/intra.15.links | linker4.py -d -a 4 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-15.out 2> merge_links/links.4-15.out.err
cat link_chunks/inter.1-8.links link_chunks/intra.1.links link_chunks/intra.8.links | linker4.py -d -a 1 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-8.out 2> merge_links/links.1-8.out.err
cat link_chunks/inter.0-3.links link_chunks/intra.0.links link_chunks/intra.3.links | linker4.py -d -a 0 -b 3 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.3.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-3.out 2> merge_links/links.0-3.out.err
cat link_chunks/inter.3-4.links link_chunks/intra.3.links link_chunks/intra.4.links | linker4.py -d -a 3 -b 4 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.4.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-4.out 2> merge_links/links.3-4.out.err
cat link_chunks/inter.2-8.links link_chunks/intra.2.links link_chunks/intra.8.links | linker4.py -d -a 2 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-8.out 2> merge_links/links.2-8.out.err
cat link_chunks/inter.4-4.links link_chunks/intra.4.links link_chunks/intra.4.links | linker4.py -d -a 4 -b 4 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.4.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-4.out 2> merge_links/links.4-4.out.err
cat link_chunks/inter.1-7.links link_chunks/intra.1.links link_chunks/intra.7.links | linker4.py -d -a 1 -b 7 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.7.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-7.out 2> merge_links/links.1-7.out.err
cat link_chunks/inter.4-9.links link_chunks/intra.4.links link_chunks/intra.9.links | linker4.py -d -a 4 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-9.out 2> merge_links/links.4-9.out.err
cat link_chunks/inter.5-12.links link_chunks/intra.5.links link_chunks/intra.12.links | linker4.py -d -a 5 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-12.out 2> merge_links/links.5-12.out.err
cat link_chunks/inter.2-14.links link_chunks/intra.2.links link_chunks/intra.14.links | linker4.py -d -a 2 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-14.out 2> merge_links/links.2-14.out.err
cat link_chunks/inter.14-15.links link_chunks/intra.14.links link_chunks/intra.15.links | linker4.py -d -a 14 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.14.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.14-15.out 2> merge_links/links.14-15.out.err
cat link_chunks/inter.3-13.links link_chunks/intra.3.links link_chunks/intra.13.links | linker4.py -d -a 3 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-13.out 2> merge_links/links.3-13.out.err
cat link_chunks/inter.10-14.links link_chunks/intra.10.links link_chunks/intra.14.links | linker4.py -d -a 10 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.10.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.10-14.out 2> merge_links/links.10-14.out.err
cat link_chunks/inter.4-12.links link_chunks/intra.4.links link_chunks/intra.12.links | linker4.py -d -a 4 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-12.out 2> merge_links/links.4-12.out.err
cat link_chunks/inter.4-13.links link_chunks/intra.4.links link_chunks/intra.13.links | linker4.py -d -a 4 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-13.out 2> merge_links/links.4-13.out.err
cat link_chunks/inter.1-1.links link_chunks/intra.1.links link_chunks/intra.1.links | linker4.py -d -a 1 -b 1 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.1.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-1.out 2> merge_links/links.1-1.out.err
cat link_chunks/inter.3-5.links link_chunks/intra.3.links link_chunks/intra.5.links | linker4.py -d -a 3 -b 5 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.5.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-5.out 2> merge_links/links.3-5.out.err
cat link_chunks/inter.2-2.links link_chunks/intra.2.links link_chunks/intra.2.links | linker4.py -d -a 2 -b 2 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.2.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-2.out 2> merge_links/links.2-2.out.err
cat link_chunks/inter.1-2.links link_chunks/intra.1.links link_chunks/intra.2.links | linker4.py -d -a 1 -b 2 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.2.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-2.out 2> merge_links/links.1-2.out.err
cat link_chunks/inter.3-15.links link_chunks/intra.3.links link_chunks/intra.15.links | linker4.py -d -a 3 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-15.out 2> merge_links/links.3-15.out.err
cat link_chunks/inter.12-15.links link_chunks/intra.12.links link_chunks/intra.15.links | linker4.py -d -a 12 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.12.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.12-15.out 2> merge_links/links.12-15.out.err
cat link_chunks/inter.11-15.links link_chunks/intra.11.links link_chunks/intra.15.links | linker4.py -d -a 11 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.11.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.11-15.out 2> merge_links/links.11-15.out.err
cat link_chunks/inter.11-11.links link_chunks/intra.11.links link_chunks/intra.11.links | linker4.py -d -a 11 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.11.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.11-11.out 2> merge_links/links.11-11.out.err
cat link_chunks/inter.5-8.links link_chunks/intra.5.links link_chunks/intra.8.links | linker4.py -d -a 5 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-8.out 2> merge_links/links.5-8.out.err
cat link_chunks/inter.1-10.links link_chunks/intra.1.links link_chunks/intra.10.links | linker4.py -d -a 1 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-10.out 2> merge_links/links.1-10.out.err
cat link_chunks/inter.8-10.links link_chunks/intra.8.links link_chunks/intra.10.links | linker4.py -d -a 8 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.8.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.8-10.out 2> merge_links/links.8-10.out.err
cat link_chunks/inter.1-14.links link_chunks/intra.1.links link_chunks/intra.14.links | linker4.py -d -a 1 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-14.out 2> merge_links/links.1-14.out.err
cat link_chunks/inter.7-8.links link_chunks/intra.7.links link_chunks/intra.8.links | linker4.py -d -a 7 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-8.out 2> merge_links/links.7-8.out.err
cat link_chunks/inter.0-12.links link_chunks/intra.0.links link_chunks/intra.12.links | linker4.py -d -a 0 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-12.out 2> merge_links/links.0-12.out.err
cat link_chunks/inter.0-7.links link_chunks/intra.0.links link_chunks/intra.7.links | linker4.py -d -a 0 -b 7 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.7.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-7.out 2> merge_links/links.0-7.out.err
cat link_chunks/inter.1-11.links link_chunks/intra.1.links link_chunks/intra.11.links | linker4.py -d -a 1 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-11.out 2> merge_links/links.1-11.out.err
cat link_chunks/inter.0-2.links link_chunks/intra.0.links link_chunks/intra.2.links | linker4.py -d -a 0 -b 2 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.2.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-2.out 2> merge_links/links.0-2.out.err
cat link_chunks/inter.7-11.links link_chunks/intra.7.links link_chunks/intra.11.links | linker4.py -d -a 7 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-11.out 2> merge_links/links.7-11.out.err
cat link_chunks/inter.13-15.links link_chunks/intra.13.links link_chunks/intra.15.links | linker4.py -d -a 13 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.13.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.13-15.out 2> merge_links/links.13-15.out.err
cat link_chunks/inter.0-4.links link_chunks/intra.0.links link_chunks/intra.4.links | linker4.py -d -a 0 -b 4 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.4.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-4.out 2> merge_links/links.0-4.out.err
cat link_chunks/inter.11-14.links link_chunks/intra.11.links link_chunks/intra.14.links | linker4.py -d -a 11 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.11.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.11-14.out 2> merge_links/links.11-14.out.err
cat link_chunks/inter.5-10.links link_chunks/intra.5.links link_chunks/intra.10.links | linker4.py -d -a 5 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-10.out 2> merge_links/links.5-10.out.err
cat link_chunks/inter.2-9.links link_chunks/intra.2.links link_chunks/intra.9.links | linker4.py -d -a 2 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-9.out 2> merge_links/links.2-9.out.err
cat link_chunks/inter.7-15.links link_chunks/intra.7.links link_chunks/intra.15.links | linker4.py -d -a 7 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-15.out 2> merge_links/links.7-15.out.err
cat link_chunks/inter.1-3.links link_chunks/intra.1.links link_chunks/intra.3.links | linker4.py -d -a 1 -b 3 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.3.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-3.out 2> merge_links/links.1-3.out.err
cat link_chunks/inter.3-9.links link_chunks/intra.3.links link_chunks/intra.9.links | linker4.py -d -a 3 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-9.out 2> merge_links/links.3-9.out.err
cat link_chunks/inter.7-13.links link_chunks/intra.7.links link_chunks/intra.13.links | linker4.py -d -a 7 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-13.out 2> merge_links/links.7-13.out.err
cat link_chunks/inter.4-10.links link_chunks/intra.4.links link_chunks/intra.10.links | linker4.py -d -a 4 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-10.out 2> merge_links/links.4-10.out.err
cat link_chunks/inter.3-14.links link_chunks/intra.3.links link_chunks/intra.14.links | linker4.py -d -a 3 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-14.out 2> merge_links/links.3-14.out.err
cat link_chunks/inter.1-13.links link_chunks/intra.1.links link_chunks/intra.13.links | linker4.py -d -a 1 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-13.out 2> merge_links/links.1-13.out.err
cat link_chunks/inter.1-15.links link_chunks/intra.1.links link_chunks/intra.15.links | linker4.py -d -a 1 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-15.out 2> merge_links/links.1-15.out.err
cat link_chunks/inter.6-15.links link_chunks/intra.6.links link_chunks/intra.15.links | linker4.py -d -a 6 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-15.out 2> merge_links/links.6-15.out.err
cat link_chunks/inter.2-3.links link_chunks/intra.2.links link_chunks/intra.3.links | linker4.py -d -a 2 -b 3 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.3.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-3.out 2> merge_links/links.2-3.out.err
cat link_chunks/inter.5-11.links link_chunks/intra.5.links link_chunks/intra.11.links | linker4.py -d -a 5 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-11.out 2> merge_links/links.5-11.out.err
cat link_chunks/inter.0-0.links link_chunks/intra.0.links link_chunks/intra.0.links | linker4.py -d -a 0 -b 0 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.0.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-0.out 2> merge_links/links.0-0.out.err
cat link_chunks/inter.9-14.links link_chunks/intra.9.links link_chunks/intra.14.links | linker4.py -d -a 9 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.9.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.9-14.out 2> merge_links/links.9-14.out.err
cat link_chunks/inter.7-10.links link_chunks/intra.7.links link_chunks/intra.10.links | linker4.py -d -a 7 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-10.out 2> merge_links/links.7-10.out.err
cat link_chunks/inter.1-5.links link_chunks/intra.1.links link_chunks/intra.5.links | linker4.py -d -a 1 -b 5 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.5.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-5.out 2> merge_links/links.1-5.out.err
cat link_chunks/inter.8-13.links link_chunks/intra.8.links link_chunks/intra.13.links | linker4.py -d -a 8 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.8.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.8-13.out 2> merge_links/links.8-13.out.err
cat link_chunks/inter.2-6.links link_chunks/intra.2.links link_chunks/intra.6.links | linker4.py -d -a 2 -b 6 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.6.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-6.out 2> merge_links/links.2-6.out.err
cat link_chunks/inter.0-10.links link_chunks/intra.0.links link_chunks/intra.10.links | linker4.py -d -a 0 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-10.out 2> merge_links/links.0-10.out.err
cat link_chunks/inter.8-9.links link_chunks/intra.8.links link_chunks/intra.9.links | linker4.py -d -a 8 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.8.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.8-9.out 2> merge_links/links.8-9.out.err
cat link_chunks/inter.0-13.links link_chunks/intra.0.links link_chunks/intra.13.links | linker4.py -d -a 0 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-13.out 2> merge_links/links.0-13.out.err
cat link_chunks/inter.0-6.links link_chunks/intra.0.links link_chunks/intra.6.links | linker4.py -d -a 0 -b 6 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.6.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-6.out 2> merge_links/links.0-6.out.err
cat link_chunks/inter.8-12.links link_chunks/intra.8.links link_chunks/intra.12.links | linker4.py -d -a 8 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.8.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.8-12.out 2> merge_links/links.8-12.out.err
cat link_chunks/inter.6-11.links link_chunks/intra.6.links link_chunks/intra.11.links | linker4.py -d -a 6 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-11.out 2> merge_links/links.6-11.out.err
cat link_chunks/inter.9-11.links link_chunks/intra.9.links link_chunks/intra.11.links | linker4.py -d -a 9 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.9.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.9-11.out 2> merge_links/links.9-11.out.err
cat link_chunks/inter.9-13.links link_chunks/intra.9.links link_chunks/intra.13.links | linker4.py -d -a 9 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.9.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.9-13.out 2> merge_links/links.9-13.out.err
cat link_chunks/inter.6-8.links link_chunks/intra.6.links link_chunks/intra.8.links | linker4.py -d -a 6 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-8.out 2> merge_links/links.6-8.out.err
cat link_chunks/inter.8-14.links link_chunks/intra.8.links link_chunks/intra.14.links | linker4.py -d -a 8 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.8.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.8-14.out 2> merge_links/links.8-14.out.err
cat link_chunks/inter.10-13.links link_chunks/intra.10.links link_chunks/intra.13.links | linker4.py -d -a 10 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.10.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.10-13.out 2> merge_links/links.10-13.out.err
cat link_chunks/inter.1-6.links link_chunks/intra.1.links link_chunks/intra.6.links | linker4.py -d -a 1 -b 6 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.6.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-6.out 2> merge_links/links.1-6.out.err
cat link_chunks/inter.2-10.links link_chunks/intra.2.links link_chunks/intra.10.links | linker4.py -d -a 2 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-10.out 2> merge_links/links.2-10.out.err
cat link_chunks/inter.3-7.links link_chunks/intra.3.links link_chunks/intra.7.links | linker4.py -d -a 3 -b 7 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.7.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-7.out 2> merge_links/links.3-7.out.err
cat link_chunks/inter.3-11.links link_chunks/intra.3.links link_chunks/intra.11.links | linker4.py -d -a 3 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-11.out 2> merge_links/links.3-11.out.err
cat link_chunks/inter.2-11.links link_chunks/intra.2.links link_chunks/intra.11.links | linker4.py -d -a 2 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-11.out 2> merge_links/links.2-11.out.err
cat link_chunks/inter.9-15.links link_chunks/intra.9.links link_chunks/intra.15.links | linker4.py -d -a 9 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.9.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.9-15.out 2> merge_links/links.9-15.out.err
cat link_chunks/inter.2-4.links link_chunks/intra.2.links link_chunks/intra.4.links | linker4.py -d -a 2 -b 4 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.4.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-4.out 2> merge_links/links.2-4.out.err
cat link_chunks/inter.4-5.links link_chunks/intra.4.links link_chunks/intra.5.links | linker4.py -d -a 4 -b 5 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.5.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-5.out 2> merge_links/links.4-5.out.err
cat link_chunks/inter.10-12.links link_chunks/intra.10.links link_chunks/intra.12.links | linker4.py -d -a 10 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.10.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.10-12.out 2> merge_links/links.10-12.out.err
cat link_chunks/inter.0-15.links link_chunks/intra.0.links link_chunks/intra.15.links | linker4.py -d -a 0 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-15.out 2> merge_links/links.0-15.out.err
cat link_chunks/inter.9-9.links link_chunks/intra.9.links link_chunks/intra.9.links | linker4.py -d -a 9 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.9.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.9-9.out 2> merge_links/links.9-9.out.err
cat link_chunks/inter.6-14.links link_chunks/intra.6.links link_chunks/intra.14.links | linker4.py -d -a 6 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-14.out 2> merge_links/links.6-14.out.err
cat link_chunks/inter.10-10.links link_chunks/intra.10.links link_chunks/intra.10.links | linker4.py -d -a 10 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.10.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.10-10.out 2> merge_links/links.10-10.out.err
cat link_chunks/inter.0-8.links link_chunks/intra.0.links link_chunks/intra.8.links | linker4.py -d -a 0 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-8.out 2> merge_links/links.0-8.out.err
cat link_chunks/inter.3-8.links link_chunks/intra.3.links link_chunks/intra.8.links | linker4.py -d -a 3 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-8.out 2> merge_links/links.3-8.out.err
cat link_chunks/inter.4-6.links link_chunks/intra.4.links link_chunks/intra.6.links | linker4.py -d -a 4 -b 6 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.6.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-6.out 2> merge_links/links.4-6.out.err
cat link_chunks/inter.5-13.links link_chunks/intra.5.links link_chunks/intra.13.links | linker4.py -d -a 5 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-13.out 2> merge_links/links.5-13.out.err
cat link_chunks/inter.12-14.links link_chunks/intra.12.links link_chunks/intra.14.links | linker4.py -d -a 12 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.12.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.12-14.out 2> merge_links/links.12-14.out.err
cat link_chunks/inter.11-12.links link_chunks/intra.11.links link_chunks/intra.12.links | linker4.py -d -a 11 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.11.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.11-12.out 2> merge_links/links.11-12.out.err
cat link_chunks/inter.5-7.links link_chunks/intra.5.links link_chunks/intra.7.links | linker4.py -d -a 5 -b 7 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.7.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-7.out 2> merge_links/links.5-7.out.err
cat link_chunks/inter.2-7.links link_chunks/intra.2.links link_chunks/intra.7.links | linker4.py -d -a 2 -b 7 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.7.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-7.out 2> merge_links/links.2-7.out.err
cat link_chunks/inter.4-8.links link_chunks/intra.4.links link_chunks/intra.8.links | linker4.py -d -a 4 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-8.out 2> merge_links/links.4-8.out.err
cat link_chunks/inter.1-4.links link_chunks/intra.1.links link_chunks/intra.4.links | linker4.py -d -a 1 -b 4 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.4.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-4.out 2> merge_links/links.1-4.out.err
cat link_chunks/inter.6-10.links link_chunks/intra.6.links link_chunks/intra.10.links | linker4.py -d -a 6 -b 10 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.10.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-10.out 2> merge_links/links.6-10.out.err
cat link_chunks/inter.0-1.links link_chunks/intra.0.links link_chunks/intra.1.links | linker4.py -d -a 0 -b 1 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.1.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-1.out 2> merge_links/links.0-1.out.err
cat link_chunks/inter.0-9.links link_chunks/intra.0.links link_chunks/intra.9.links | linker4.py -d -a 0 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-9.out 2> merge_links/links.0-9.out.err
cat link_chunks/inter.0-11.links link_chunks/intra.0.links link_chunks/intra.11.links | linker4.py -d -a 0 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-11.out 2> merge_links/links.0-11.out.err
cat link_chunks/inter.2-12.links link_chunks/intra.2.links link_chunks/intra.12.links | linker4.py -d -a 2 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-12.out 2> merge_links/links.2-12.out.err
cat link_chunks/inter.1-12.links link_chunks/intra.1.links link_chunks/intra.12.links | linker4.py -d -a 1 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-12.out 2> merge_links/links.1-12.out.err
cat link_chunks/inter.11-13.links link_chunks/intra.11.links link_chunks/intra.13.links | linker4.py -d -a 11 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.11.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.11-13.out 2> merge_links/links.11-13.out.err
cat link_chunks/inter.8-11.links link_chunks/intra.8.links link_chunks/intra.11.links | linker4.py -d -a 8 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.8.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.8-11.out 2> merge_links/links.8-11.out.err
cat link_chunks/inter.3-3.links link_chunks/intra.3.links link_chunks/intra.3.links | linker4.py -d -a 3 -b 3 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.3.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-3.out 2> merge_links/links.3-3.out.err
cat link_chunks/inter.7-7.links link_chunks/intra.7.links link_chunks/intra.7.links | linker4.py -d -a 7 -b 7 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.7.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-7.out 2> merge_links/links.7-7.out.err
cat link_chunks/inter.7-14.links link_chunks/intra.7.links link_chunks/intra.14.links | linker4.py -d -a 7 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-14.out 2> merge_links/links.7-14.out.err
cat link_chunks/inter.8-8.links link_chunks/intra.8.links link_chunks/intra.8.links | linker4.py -d -a 8 -b 8 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.8.out refined.8.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.8-8.out 2> merge_links/links.8-8.out.err
cat link_chunks/inter.15-15.links link_chunks/intra.15.links link_chunks/intra.15.links | linker4.py -d -a 15 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.15.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.15-15.out 2> merge_links/links.15-15.out.err
cat link_chunks/inter.13-13.links link_chunks/intra.13.links link_chunks/intra.13.links | linker4.py -d -a 13 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.13.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.13-13.out 2> merge_links/links.13-13.out.err
cat link_chunks/inter.3-6.links link_chunks/intra.3.links link_chunks/intra.6.links | linker4.py -d -a 3 -b 6 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.3.out refined.6.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.3-6.out 2> merge_links/links.3-6.out.err
cat link_chunks/inter.13-14.links link_chunks/intra.13.links link_chunks/intra.14.links | linker4.py -d -a 13 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.13.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.13-14.out 2> merge_links/links.13-14.out.err
cat link_chunks/inter.10-15.links link_chunks/intra.10.links link_chunks/intra.15.links | linker4.py -d -a 10 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.10.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.10-15.out 2> merge_links/links.10-15.out.err
cat link_chunks/inter.5-9.links link_chunks/intra.5.links link_chunks/intra.9.links | linker4.py -d -a 5 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-9.out 2> merge_links/links.5-9.out.err
cat link_chunks/inter.7-12.links link_chunks/intra.7.links link_chunks/intra.12.links | linker4.py -d -a 7 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.7.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.7-12.out 2> merge_links/links.7-12.out.err
cat link_chunks/inter.6-13.links link_chunks/intra.6.links link_chunks/intra.13.links | linker4.py -d -a 6 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-13.out 2> merge_links/links.6-13.out.err
cat link_chunks/inter.4-7.links link_chunks/intra.4.links link_chunks/intra.7.links | linker4.py -d -a 4 -b 7 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.7.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-7.out 2> merge_links/links.4-7.out.err
cat link_chunks/inter.5-15.links link_chunks/intra.5.links link_chunks/intra.15.links | linker4.py -d -a 5 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-15.out 2> merge_links/links.5-15.out.err
cat link_chunks/inter.1-9.links link_chunks/intra.1.links link_chunks/intra.9.links | linker4.py -d -a 1 -b 9 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.1.out refined.9.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.1-9.out 2> merge_links/links.1-9.out.err
cat link_chunks/inter.4-14.links link_chunks/intra.4.links link_chunks/intra.14.links | linker4.py -d -a 4 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.4.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.4-14.out 2> merge_links/links.4-14.out.err
cat link_chunks/inter.10-11.links link_chunks/intra.10.links link_chunks/intra.11.links | linker4.py -d -a 10 -b 11 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.10.out refined.11.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.10-11.out 2> merge_links/links.10-11.out.err
cat link_chunks/inter.0-14.links link_chunks/intra.0.links link_chunks/intra.14.links | linker4.py -d -a 0 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-14.out 2> merge_links/links.0-14.out.err
cat link_chunks/inter.6-7.links link_chunks/intra.6.links link_chunks/intra.7.links | linker4.py -d -a 6 -b 7 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.7.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-7.out 2> merge_links/links.6-7.out.err
cat link_chunks/inter.9-12.links link_chunks/intra.9.links link_chunks/intra.12.links | linker4.py -d -a 9 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.9.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.9-12.out 2> merge_links/links.9-12.out.err
cat link_chunks/inter.2-13.links link_chunks/intra.2.links link_chunks/intra.13.links | linker4.py -d -a 2 -b 13 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.13.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-13.out 2> merge_links/links.2-13.out.err
cat link_chunks/inter.2-15.links link_chunks/intra.2.links link_chunks/intra.15.links | linker4.py -d -a 2 -b 15 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.15.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-15.out 2> merge_links/links.2-15.out.err
cat link_chunks/inter.0-5.links link_chunks/intra.0.links link_chunks/intra.5.links | linker4.py -d -a 0 -b 5 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.0.out refined.5.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.0-5.out 2> merge_links/links.0-5.out.err
cat link_chunks/inter.5-6.links link_chunks/intra.5.links link_chunks/intra.6.links | linker4.py -d -a 5 -b 6 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.6.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-6.out 2> merge_links/links.5-6.out.err
cat link_chunks/inter.5-14.links link_chunks/intra.5.links link_chunks/intra.14.links | linker4.py -d -a 5 -b 14 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.14.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-14.out 2> merge_links/links.5-14.out.err
cat link_chunks/inter.6-6.links link_chunks/intra.6.links link_chunks/intra.6.links | linker4.py -d -a 6 -b 6 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.6.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-6.out 2> merge_links/links.6-6.out.err
cat link_chunks/inter.6-12.links link_chunks/intra.6.links link_chunks/intra.12.links | linker4.py -d -a 6 -b 12 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.6.out refined.12.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.6-12.out 2> merge_links/links.6-12.out.err
cat link_chunks/inter.2-5.links link_chunks/intra.2.links link_chunks/intra.5.links | linker4.py -d -a 2 -b 5 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.2.out refined.5.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.2-5.out 2> merge_links/links.2-5.out.err
cat link_chunks/inter.5-5.links link_chunks/intra.5.links link_chunks/intra.5.links | linker4.py -d -a 5 -b 5 -Z component_x.txt -l broken_lengths.txt -p -L - -s <( cat refined.5.out refined.5.out ) --set_insert_size_dist_fit_params datamodel.out > merge_links/links.5-5.out 2> merge_links/links.5-5.out.err

cat merge_links/links.0-0.out merge_links/links.0-1.out merge_links/links.1-1.out merge_links/links.0-2.out merge_links/links.1-2.out merge_links/links.2-2.out merge_links/links.0-3.out merge_links/links.1-3.out merge_links/links.2-3.out merge_links/links.3-3.out merge_links/links.0-4.out merge_links/links.1-4.out merge_links/links.2-4.out merge_links/links.3-4.out merge_links/links.4-4.out merge_links/links.0-5.out merge_links/links.1-5.out merge_links/links.2-5.out merge_links/links.3-5.out merge_links/links.4-5.out merge_links/links.5-5.out merge_links/links.0-6.out merge_links/links.1-6.out merge_links/links.2-6.out merge_links/links.3-6.out merge_links/links.4-6.out merge_links/links.5-6.out merge_links/links.6-6.out merge_links/links.0-7.out merge_links/links.1-7.out merge_links/links.2-7.out merge_links/links.3-7.out merge_links/links.4-7.out merge_links/links.5-7.out merge_links/links.6-7.out merge_links/links.7-7.out merge_links/links.0-8.out merge_links/links.1-8.out merge_links/links.2-8.out merge_links/links.3-8.out merge_links/links.4-8.out merge_links/links.5-8.out merge_links/links.6-8.out merge_links/links.7-8.out merge_links/links.8-8.out merge_links/links.0-9.out merge_links/links.1-9.out merge_links/links.2-9.out merge_links/links.3-9.out merge_links/links.4-9.out merge_links/links.5-9.out merge_links/links.6-9.out merge_links/links.7-9.out merge_links/links.8-9.out merge_links/links.9-9.out merge_links/links.0-10.out merge_links/links.1-10.out merge_links/links.2-10.out merge_links/links.3-10.out merge_links/links.4-10.out merge_links/links.5-10.out merge_links/links.6-10.out merge_links/links.7-10.out merge_links/links.8-10.out merge_links/links.9-10.out merge_links/links.10-10.out merge_links/links.0-11.out merge_links/links.1-11.out merge_links/links.2-11.out merge_links/links.3-11.out merge_links/links.4-11.out merge_links/links.5-11.out merge_links/links.6-11.out merge_links/links.7-11.out merge_links/links.8-11.out merge_links/links.9-11.out merge_links/links.10-11.out merge_links/links.11-11.out merge_links/links.0-12.out merge_links/links.1-12.out merge_links/links.2-12.out merge_links/links.3-12.out merge_links/links.4-12.out merge_links/links.5-12.out merge_links/links.6-12.out merge_links/links.7-12.out merge_links/links.8-12.out merge_links/links.9-12.out merge_links/links.10-12.out merge_links/links.11-12.out merge_links/links.12-12.out merge_links/links.0-13.out merge_links/links.1-13.out merge_links/links.2-13.out merge_links/links.3-13.out merge_links/links.4-13.out merge_links/links.5-13.out merge_links/links.6-13.out merge_links/links.7-13.out merge_links/links.8-13.out merge_links/links.9-13.out merge_links/links.10-13.out merge_links/links.11-13.out merge_links/links.12-13.out merge_links/links.13-13.out merge_links/links.0-14.out merge_links/links.1-14.out merge_links/links.2-14.out merge_links/links.3-14.out merge_links/links.4-14.out merge_links/links.5-14.out merge_links/links.6-14.out merge_links/links.7-14.out merge_links/links.8-14.out merge_links/links.9-14.out merge_links/links.10-14.out merge_links/links.11-14.out merge_links/links.12-14.out merge_links/links.13-14.out merge_links/links.14-14.out merge_links/links.0-15.out merge_links/links.1-15.out merge_links/links.2-15.out merge_links/links.3-15.out merge_links/links.4-15.out merge_links/links.5-15.out merge_links/links.6-15.out merge_links/links.7-15.out merge_links/links.8-15.out merge_links/links.9-15.out merge_links/links.10-15.out merge_links/links.11-15.out merge_links/links.12-15.out merge_links/links.13-15.out merge_links/links.14-15.out merge_links/links.15-15.out | hiriseJoin.py -m 20.0 -s <( cat refined.0.out refined.1.out refined.2.out refined.3.out refined.4.out refined.5.out refined.6.out refined.7.out refined.8.out refined.9.out refined.10.out refined.11.out refined.12.out refined.13.out refined.14.out refined.15.out) -l  broken_lengths.txt > hirise.out

cp hirise.out hirise_iter_0.out
set_layout.py -i assembly1.hra -o hirise_iter_0.hra -L hirise_iter_0.out


for k in {0..7};do
 {
  parallel_breaker.py -i hirise_iter_0.hra -o chicago_weak_segs_iter0_part$k.out -t 20 -T 30 -q $qual2 -j 2 -S $k,8 -H chicago_weak_segs_iter0_part$k.out.histogram > pb0-$k.out 2> pb0-$k.err
 } &
done
wait

cat chicago_weak_segs_iter0_part0.out chicago_weak_segs_iter0_part1.out chicago_weak_segs_iter0_part2.out chicago_weak_segs_iter0_part3.out chicago_weak_segs_iter0_part4.out chicago_weak_segs_iter0_part5.out chicago_weak_segs_iter0_part6.out chicago_weak_segs_iter0_part7.out > chicago_weak_segs_iter0.out

break_playout.py -T 0.0 -t 0.0 -i hirise_iter_0.out -o hirise_iter_broken_0.out -b chicago_weak_segs_iter0.out > hirise_iter_broken_0.log
set_layout.py -i assembly1.hra -o r0.hra -L hirise_iter_broken_0.out

for k in {0..15};do
 {
  if [ ! -e  hirise_iter_broken_links_0 ] ; then mkdir hirise_iter_broken_links_0 ; fi ; export_links.py -q $qual2 -i r0.hra -c $k  -C 16 > hirise_iter_broken_links_0/$k.links  
 } &
done
wait

for k in {0..15};do
 {
  cat hirise_iter_broken_0.out | local_oo_opt.py -N 16 -a $k -l "hirise_iter_broken_links_0/*.links" -M datamodel.out > merge_links_tmp/refined_0.$k.out  
 } &
done
wait


cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-11.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 3 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-3.out
cat merge_links_tmp/refined_0.9.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.9-13.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-8.out
cat merge_links_tmp/refined_0.14.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 14 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.14-14.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.1.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 1 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-1.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 7 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-7.out
cat merge_links_tmp/refined_0.9.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.9-9.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-8.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 5 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-5.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-10.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-12.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-15.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-13.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 4 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-4.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-12.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 6 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-6.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-8.out
cat merge_links_tmp/refined_0.15.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 15 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.15-15.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-12.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-11.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 4 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-4.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-15.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 7 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-7.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-15.out
cat merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.8-10.out
cat merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.8-11.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 6 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-6.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 6 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-6.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 4 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-4.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-13.out
cat merge_links_tmp/refined_0.9.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.9-11.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 7 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-7.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 5 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-5.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-14.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-13.out
cat merge_links_tmp/refined_0.11.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.11-13.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 4 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-4.out
cat merge_links_tmp/refined_0.10.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.10-10.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 2 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-2.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 4 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-4.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-14.out
cat merge_links_tmp/refined_0.13.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.13-14.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-11.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-15.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-12.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 3 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-3.out
cat merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.8-8.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 2 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-2.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 6 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-6.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 7 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-7.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-10.out
cat merge_links_tmp/refined_0.11.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.11-12.out
cat merge_links_tmp/refined_0.10.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.10-12.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-11.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-10.out
cat merge_links_tmp/refined_0.12.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.12-12.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-14.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-14.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-13.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-10.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-14.out
cat merge_links_tmp/refined_0.12.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.12-13.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-9.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-11.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-14.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-9.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-12.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-9.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-10.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-8.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-15.out
cat merge_links_tmp/refined_0.11.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.11-11.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 6 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-6.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-8.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-14.out
cat merge_links_tmp/refined_0.12.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.12-14.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 6 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-6.out
cat merge_links_tmp/refined_0.9.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.9-15.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-9.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-15.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-10.out
cat merge_links_tmp/refined_0.13.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.13-15.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.0.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 0 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-0.out
cat merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.8-15.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.1.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 1 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-1.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-9.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 7 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-7.out
cat merge_links_tmp/refined_0.14.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 14 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.14-15.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-8.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 2 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-2.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-9.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-13.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 7 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-7.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-15.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-12.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 5 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-5.out
cat merge_links_tmp/refined_0.9.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.9-14.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-12.out
cat merge_links_tmp/refined_0.10.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.10-14.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 3 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-3.out
cat merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.8-14.out
cat merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.8-12.out
cat merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.5-14.out
cat merge_links_tmp/refined_0.12.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.12-15.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-13.out
cat merge_links_tmp/refined_0.11.out merge_links_tmp/refined_0.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 14 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.11-14.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 7 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-7.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-13.out
cat merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.6-15.out
cat merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.8-13.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-10.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 6 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-6.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 3 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-3.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-13.out
cat merge_links_tmp/refined_0.10.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.10-15.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-10.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-12.out
cat merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 5 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.2-5.out
cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.0-11.out
cat merge_links_tmp/refined_0.11.out merge_links_tmp/refined_0.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 15 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.11-15.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 5 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-5.out
cat merge_links_tmp/refined_0.9.out merge_links_tmp/refined_0.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 10 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.9-10.out
cat merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.7-11.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-9.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-9.out
cat merge_links_tmp/refined_0.13.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.13-13.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-11.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 7 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-7.out
cat merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.1-8.out
cat merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 8 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.3-8.out
cat merge_links_tmp/refined_0.10.out merge_links_tmp/refined_0.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 11 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.10-11.out
cat merge_links_tmp/refined_0.9.out merge_links_tmp/refined_0.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 12 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.9-12.out
cat merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 5 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.4-5.out
cat merge_links_tmp/refined_0.10.out merge_links_tmp/refined_0.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 13 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.10-13.out
cat merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 9 -L "hirise_iter_broken_links_0/*.links" -d -M datamodel.out > merge_links_tmp/links_0.8-9.out
cat merge_links_tmp/links_0.0-0.out merge_links_tmp/links_0.0-1.out merge_links_tmp/links_0.1-1.out merge_links_tmp/links_0.0-2.out merge_links_tmp/links_0.1-2.out merge_links_tmp/links_0.2-2.out merge_links_tmp/links_0.0-3.out merge_links_tmp/links_0.1-3.out merge_links_tmp/links_0.2-3.out merge_links_tmp/links_0.3-3.out merge_links_tmp/links_0.0-4.out merge_links_tmp/links_0.1-4.out merge_links_tmp/links_0.2-4.out merge_links_tmp/links_0.3-4.out merge_links_tmp/links_0.4-4.out merge_links_tmp/links_0.0-5.out merge_links_tmp/links_0.1-5.out merge_links_tmp/links_0.2-5.out merge_links_tmp/links_0.3-5.out merge_links_tmp/links_0.4-5.out merge_links_tmp/links_0.5-5.out merge_links_tmp/links_0.0-6.out merge_links_tmp/links_0.1-6.out merge_links_tmp/links_0.2-6.out merge_links_tmp/links_0.3-6.out merge_links_tmp/links_0.4-6.out merge_links_tmp/links_0.5-6.out merge_links_tmp/links_0.6-6.out merge_links_tmp/links_0.0-7.out merge_links_tmp/links_0.1-7.out merge_links_tmp/links_0.2-7.out merge_links_tmp/links_0.3-7.out merge_links_tmp/links_0.4-7.out merge_links_tmp/links_0.5-7.out merge_links_tmp/links_0.6-7.out merge_links_tmp/links_0.7-7.out merge_links_tmp/links_0.0-8.out merge_links_tmp/links_0.1-8.out merge_links_tmp/links_0.2-8.out merge_links_tmp/links_0.3-8.out merge_links_tmp/links_0.4-8.out merge_links_tmp/links_0.5-8.out merge_links_tmp/links_0.6-8.out merge_links_tmp/links_0.7-8.out merge_links_tmp/links_0.8-8.out merge_links_tmp/links_0.0-9.out merge_links_tmp/links_0.1-9.out merge_links_tmp/links_0.2-9.out merge_links_tmp/links_0.3-9.out merge_links_tmp/links_0.4-9.out merge_links_tmp/links_0.5-9.out merge_links_tmp/links_0.6-9.out merge_links_tmp/links_0.7-9.out merge_links_tmp/links_0.8-9.out merge_links_tmp/links_0.9-9.out merge_links_tmp/links_0.0-10.out merge_links_tmp/links_0.1-10.out merge_links_tmp/links_0.2-10.out merge_links_tmp/links_0.3-10.out merge_links_tmp/links_0.4-10.out merge_links_tmp/links_0.5-10.out merge_links_tmp/links_0.6-10.out merge_links_tmp/links_0.7-10.out merge_links_tmp/links_0.8-10.out merge_links_tmp/links_0.9-10.out merge_links_tmp/links_0.10-10.out merge_links_tmp/links_0.0-11.out merge_links_tmp/links_0.1-11.out merge_links_tmp/links_0.2-11.out merge_links_tmp/links_0.3-11.out merge_links_tmp/links_0.4-11.out merge_links_tmp/links_0.5-11.out merge_links_tmp/links_0.6-11.out merge_links_tmp/links_0.7-11.out merge_links_tmp/links_0.8-11.out merge_links_tmp/links_0.9-11.out merge_links_tmp/links_0.10-11.out merge_links_tmp/links_0.11-11.out merge_links_tmp/links_0.0-12.out merge_links_tmp/links_0.1-12.out merge_links_tmp/links_0.2-12.out merge_links_tmp/links_0.3-12.out merge_links_tmp/links_0.4-12.out merge_links_tmp/links_0.5-12.out merge_links_tmp/links_0.6-12.out merge_links_tmp/links_0.7-12.out merge_links_tmp/links_0.8-12.out merge_links_tmp/links_0.9-12.out merge_links_tmp/links_0.10-12.out merge_links_tmp/links_0.11-12.out merge_links_tmp/links_0.12-12.out merge_links_tmp/links_0.0-13.out merge_links_tmp/links_0.1-13.out merge_links_tmp/links_0.2-13.out merge_links_tmp/links_0.3-13.out merge_links_tmp/links_0.4-13.out merge_links_tmp/links_0.5-13.out merge_links_tmp/links_0.6-13.out merge_links_tmp/links_0.7-13.out merge_links_tmp/links_0.8-13.out merge_links_tmp/links_0.9-13.out merge_links_tmp/links_0.10-13.out merge_links_tmp/links_0.11-13.out merge_links_tmp/links_0.12-13.out merge_links_tmp/links_0.13-13.out merge_links_tmp/links_0.0-14.out merge_links_tmp/links_0.1-14.out merge_links_tmp/links_0.2-14.out merge_links_tmp/links_0.3-14.out merge_links_tmp/links_0.4-14.out merge_links_tmp/links_0.5-14.out merge_links_tmp/links_0.6-14.out merge_links_tmp/links_0.7-14.out merge_links_tmp/links_0.8-14.out merge_links_tmp/links_0.9-14.out merge_links_tmp/links_0.10-14.out merge_links_tmp/links_0.11-14.out merge_links_tmp/links_0.12-14.out merge_links_tmp/links_0.13-14.out merge_links_tmp/links_0.14-14.out merge_links_tmp/links_0.0-15.out merge_links_tmp/links_0.1-15.out merge_links_tmp/links_0.2-15.out merge_links_tmp/links_0.3-15.out merge_links_tmp/links_0.4-15.out merge_links_tmp/links_0.5-15.out merge_links_tmp/links_0.6-15.out merge_links_tmp/links_0.7-15.out merge_links_tmp/links_0.8-15.out merge_links_tmp/links_0.9-15.out merge_links_tmp/links_0.10-15.out merge_links_tmp/links_0.11-15.out merge_links_tmp/links_0.12-15.out merge_links_tmp/links_0.13-15.out merge_links_tmp/links_0.14-15.out merge_links_tmp/links_0.15-15.out | grep '^link score\|^interc:' > iter_links_0.out

dump_lengths.py -i r0.hra -o broken_lengths_0.out
cat iter_links_0.out | hiriseJoin.py -m 30.0 -s <( cat merge_links_tmp/refined_0.0.out merge_links_tmp/refined_0.1.out merge_links_tmp/refined_0.2.out merge_links_tmp/refined_0.3.out merge_links_tmp/refined_0.4.out merge_links_tmp/refined_0.5.out merge_links_tmp/refined_0.6.out merge_links_tmp/refined_0.7.out merge_links_tmp/refined_0.8.out merge_links_tmp/refined_0.9.out merge_links_tmp/refined_0.10.out merge_links_tmp/refined_0.11.out merge_links_tmp/refined_0.12.out merge_links_tmp/refined_0.13.out merge_links_tmp/refined_0.14.out merge_links_tmp/refined_0.15.out |p2edges.py ) -l broken_lengths_0.out > hirise_iter_1.out
set_layout.py -i assembly1.hra -o hirise_iter_1.hra -L hirise_iter_1.out

for k in {0..7}; do
  {
   parallel_breaker.py -i hirise_iter_1.hra -o chicago_weak_segs_iter1_part$k.out -t 20 -T 30 -q $qual2 -j 2 -S $k,8 -H chicago_weak_segs_iter1_part$k.out.histogram > pb1-$k.out 2> pb1-$k.err
  } &
done
wait
cat chicago_weak_segs_iter1_part0.out chicago_weak_segs_iter1_part1.out chicago_weak_segs_iter1_part2.out chicago_weak_segs_iter1_part3.out chicago_weak_segs_iter1_part4.out chicago_weak_segs_iter1_part5.out chicago_weak_segs_iter1_part6.out chicago_weak_segs_iter1_part7.out > chicago_weak_segs_iter1.out
break_playout.py -T 0.0 -t 0.0 -i hirise_iter_1.out -o hirise_iter_broken_1.out -b chicago_weak_segs_iter1.out > hirise_iter_broken_1.log
set_layout.py -i assembly1.hra -o r1.hra -L hirise_iter_broken_1.out

for k in {0..15}; do
  {
   if [ ! -e  hirise_iter_broken_links_1 ] ; then mkdir hirise_iter_broken_links_1 ; fi ; export_links.py -q $qual2 -i r1.hra -c $k -C 16 > hirise_iter_broken_links_1/$k.links
  } &
done
wait
for k in {0..15}; do
  {
   cat hirise_iter_broken_1.out | local_oo_opt.py -N 16 -a $k -l "hirise_iter_broken_links_1/*.links" -M datamodel.out > merge_links_tmp/refined_1.$k.out
  } &
done
wait

cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-9.out

cat merge_links_tmp/refined_1.11.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.11-14.out

cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-13.out

cat merge_links_tmp/refined_1.12.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.12-12.out

cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 6 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-6.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-12.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-8.out
cat merge_links_tmp/refined_1.9.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.9-9.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-14.out
cat merge_links_tmp/refined_1.10.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.10-12.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-10.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-13.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 5 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-5.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 2 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-2.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-14.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-8.out
cat merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.8-12.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-9.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 6 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-6.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-14.out
cat merge_links_tmp/refined_1.13.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.13-14.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-10.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 4 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-4.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-15.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 5 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-5.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 7 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-7.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-11.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-11.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 2 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-2.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.1.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 1 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-1.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-15.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 6 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-6.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-12.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-8.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-13.out
cat merge_links_tmp/refined_1.12.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.12-15.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-9.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 2 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-2.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-13.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-10.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-11.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-13.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-8.out
cat merge_links_tmp/refined_1.14.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 14 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.14-14.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-12.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 5 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-5.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-15.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-14.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 4 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-4.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-10.out
cat merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.8-13.out
cat merge_links_tmp/refined_1.15.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 15 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.15-15.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-8.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-15.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 3 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-3.out
cat merge_links_tmp/refined_1.9.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.9-13.out
cat merge_links_tmp/refined_1.10.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.10-10.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.1.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 1 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-1.out
cat merge_links_tmp/refined_1.10.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.10-13.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-12.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-9.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-11.out
cat merge_links_tmp/refined_1.9.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.9-12.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 6 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-6.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-13.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-10.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 7 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-7.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-15.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-15.out
cat merge_links_tmp/refined_1.11.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.11-13.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-10.out
cat merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.8-11.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 7 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-7.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 7 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-7.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-9.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-14.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-13.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-10.out
cat merge_links_tmp/refined_1.14.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 14 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.14-15.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 5 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-5.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-9.out
cat merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 7 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.5-7.out
cat merge_links_tmp/refined_1.11.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.11-15.out
cat merge_links_tmp/refined_1.11.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.11-12.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.0.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 0 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-0.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 7 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-7.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-13.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 3 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-3.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 5 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-5.out
cat merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.8-14.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-12.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-12.out
cat merge_links_tmp/refined_1.10.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.10-11.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 4 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-4.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 6 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-6.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-9.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 3 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-3.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-11.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 7 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-7.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 4 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-4.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-8.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-12.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 6 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-6.out
cat merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.8-8.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 6 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-6.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-8.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-15.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 5 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-5.out
cat merge_links_tmp/refined_1.10.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.10-15.out
cat merge_links_tmp/refined_1.9.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.9-15.out
cat merge_links_tmp/refined_1.12.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.12-14.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-14.out
cat merge_links_tmp/refined_1.12.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.12-13.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-11.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-14.out
cat merge_links_tmp/refined_1.9.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.9-14.out
cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.0-11.out
cat merge_links_tmp/refined_1.9.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.9-10.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 4 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-4.out
cat merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.8-9.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 3 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-3.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-10.out
cat merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 8 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.4-8.out
cat merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 12 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.7-12.out
cat merge_links_tmp/refined_1.9.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.9-11.out
cat merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.3-14.out
cat merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 9 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.6-9.out
cat merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 7 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.2-7.out
cat merge_links_tmp/refined_1.11.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.11-11.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-15.out
cat merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 11 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.1-11.out
cat merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.8-15.out
cat merge_links_tmp/refined_1.13.out merge_links_tmp/refined_1.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 13 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.13-13.out
cat merge_links_tmp/refined_1.10.out merge_links_tmp/refined_1.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 14 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.10-14.out
cat merge_links_tmp/refined_1.13.out merge_links_tmp/refined_1.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 15 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.13-15.out
cat merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 10 -L "hirise_iter_broken_links_1/*.links" -d -M datamodel.out > merge_links_tmp/links_1.8-10.out

dump_lengths.py -i r1.hra -o broken_lengths_1.out
cat merge_links_tmp/links_1.0-0.out merge_links_tmp/links_1.0-1.out merge_links_tmp/links_1.1-1.out merge_links_tmp/links_1.0-2.out merge_links_tmp/links_1.1-2.out merge_links_tmp/links_1.2-2.out merge_links_tmp/links_1.0-3.out merge_links_tmp/links_1.1-3.out merge_links_tmp/links_1.2-3.out merge_links_tmp/links_1.3-3.out merge_links_tmp/links_1.0-4.out merge_links_tmp/links_1.1-4.out merge_links_tmp/links_1.2-4.out merge_links_tmp/links_1.3-4.out merge_links_tmp/links_1.4-4.out merge_links_tmp/links_1.0-5.out merge_links_tmp/links_1.1-5.out merge_links_tmp/links_1.2-5.out merge_links_tmp/links_1.3-5.out merge_links_tmp/links_1.4-5.out merge_links_tmp/links_1.5-5.out merge_links_tmp/links_1.0-6.out merge_links_tmp/links_1.1-6.out merge_links_tmp/links_1.2-6.out merge_links_tmp/links_1.3-6.out merge_links_tmp/links_1.4-6.out merge_links_tmp/links_1.5-6.out merge_links_tmp/links_1.6-6.out merge_links_tmp/links_1.0-7.out merge_links_tmp/links_1.1-7.out merge_links_tmp/links_1.2-7.out merge_links_tmp/links_1.3-7.out merge_links_tmp/links_1.4-7.out merge_links_tmp/links_1.5-7.out merge_links_tmp/links_1.6-7.out merge_links_tmp/links_1.7-7.out merge_links_tmp/links_1.0-8.out merge_links_tmp/links_1.1-8.out merge_links_tmp/links_1.2-8.out merge_links_tmp/links_1.3-8.out merge_links_tmp/links_1.4-8.out merge_links_tmp/links_1.5-8.out merge_links_tmp/links_1.6-8.out merge_links_tmp/links_1.7-8.out merge_links_tmp/links_1.8-8.out merge_links_tmp/links_1.0-9.out merge_links_tmp/links_1.1-9.out merge_links_tmp/links_1.2-9.out merge_links_tmp/links_1.3-9.out merge_links_tmp/links_1.4-9.out merge_links_tmp/links_1.5-9.out merge_links_tmp/links_1.6-9.out merge_links_tmp/links_1.7-9.out merge_links_tmp/links_1.8-9.out merge_links_tmp/links_1.9-9.out merge_links_tmp/links_1.0-10.out merge_links_tmp/links_1.1-10.out merge_links_tmp/links_1.2-10.out merge_links_tmp/links_1.3-10.out merge_links_tmp/links_1.4-10.out merge_links_tmp/links_1.5-10.out merge_links_tmp/links_1.6-10.out merge_links_tmp/links_1.7-10.out merge_links_tmp/links_1.8-10.out merge_links_tmp/links_1.9-10.out merge_links_tmp/links_1.10-10.out merge_links_tmp/links_1.0-11.out merge_links_tmp/links_1.1-11.out merge_links_tmp/links_1.2-11.out merge_links_tmp/links_1.3-11.out merge_links_tmp/links_1.4-11.out merge_links_tmp/links_1.5-11.out merge_links_tmp/links_1.6-11.out merge_links_tmp/links_1.7-11.out merge_links_tmp/links_1.8-11.out merge_links_tmp/links_1.9-11.out merge_links_tmp/links_1.10-11.out merge_links_tmp/links_1.11-11.out merge_links_tmp/links_1.0-12.out merge_links_tmp/links_1.1-12.out merge_links_tmp/links_1.2-12.out merge_links_tmp/links_1.3-12.out merge_links_tmp/links_1.4-12.out merge_links_tmp/links_1.5-12.out merge_links_tmp/links_1.6-12.out merge_links_tmp/links_1.7-12.out merge_links_tmp/links_1.8-12.out merge_links_tmp/links_1.9-12.out merge_links_tmp/links_1.10-12.out merge_links_tmp/links_1.11-12.out merge_links_tmp/links_1.12-12.out merge_links_tmp/links_1.0-13.out merge_links_tmp/links_1.1-13.out merge_links_tmp/links_1.2-13.out merge_links_tmp/links_1.3-13.out merge_links_tmp/links_1.4-13.out merge_links_tmp/links_1.5-13.out merge_links_tmp/links_1.6-13.out merge_links_tmp/links_1.7-13.out merge_links_tmp/links_1.8-13.out merge_links_tmp/links_1.9-13.out merge_links_tmp/links_1.10-13.out merge_links_tmp/links_1.11-13.out merge_links_tmp/links_1.12-13.out merge_links_tmp/links_1.13-13.out merge_links_tmp/links_1.0-14.out merge_links_tmp/links_1.1-14.out merge_links_tmp/links_1.2-14.out merge_links_tmp/links_1.3-14.out merge_links_tmp/links_1.4-14.out merge_links_tmp/links_1.5-14.out merge_links_tmp/links_1.6-14.out merge_links_tmp/links_1.7-14.out merge_links_tmp/links_1.8-14.out merge_links_tmp/links_1.9-14.out merge_links_tmp/links_1.10-14.out merge_links_tmp/links_1.11-14.out merge_links_tmp/links_1.12-14.out merge_links_tmp/links_1.13-14.out merge_links_tmp/links_1.14-14.out merge_links_tmp/links_1.0-15.out merge_links_tmp/links_1.1-15.out merge_links_tmp/links_1.2-15.out merge_links_tmp/links_1.3-15.out merge_links_tmp/links_1.4-15.out merge_links_tmp/links_1.5-15.out merge_links_tmp/links_1.6-15.out merge_links_tmp/links_1.7-15.out merge_links_tmp/links_1.8-15.out merge_links_tmp/links_1.9-15.out merge_links_tmp/links_1.10-15.out merge_links_tmp/links_1.11-15.out merge_links_tmp/links_1.12-15.out merge_links_tmp/links_1.13-15.out merge_links_tmp/links_1.14-15.out merge_links_tmp/links_1.15-15.out | grep '^link score\|^interc:' > iter_links_1.out
cat iter_links_1.out | hiriseJoin.py -m 30.0 -s <( cat merge_links_tmp/refined_1.0.out merge_links_tmp/refined_1.1.out merge_links_tmp/refined_1.2.out merge_links_tmp/refined_1.3.out merge_links_tmp/refined_1.4.out merge_links_tmp/refined_1.5.out merge_links_tmp/refined_1.6.out merge_links_tmp/refined_1.7.out merge_links_tmp/refined_1.8.out merge_links_tmp/refined_1.9.out merge_links_tmp/refined_1.10.out merge_links_tmp/refined_1.11.out merge_links_tmp/refined_1.12.out merge_links_tmp/refined_1.13.out merge_links_tmp/refined_1.14.out merge_links_tmp/refined_1.15.out |p2edges.py ) -l broken_lengths_1.out > hirise_iter_2.out
set_layout.py -i assembly1.hra -o hirise_iter_2.hra -L hirise_iter_2.out

for k in {0..7}; do
  {
   parallel_breaker.py -i hirise_iter_2.hra -o chicago_weak_segs_iter2_part$k.out -t 20 -T 30 -q $qual2 -j 2 -S $k,8 -H chicago_weak_segs_iter2_part$k.out.histogram > pb2-$k.out 2> pb2-$k.err
  } &
done
wait

cat chicago_weak_segs_iter2_part0.out chicago_weak_segs_iter2_part1.out chicago_weak_segs_iter2_part2.out chicago_weak_segs_iter2_part3.out chicago_weak_segs_iter2_part4.out chicago_weak_segs_iter2_part5.out chicago_weak_segs_iter2_part6.out chicago_weak_segs_iter2_part7.out > chicago_weak_segs_iter2.out
break_playout.py -T 0.0 -t 0.0 -i hirise_iter_2.out -o hirise_iter_broken_2.out -b chicago_weak_segs_iter2.out > hirise_iter_broken_2.log
set_layout.py -i assembly1.hra -o r2.hra -L hirise_iter_broken_2.out

for k in {0..15}; do
  {
   if [ ! -e  hirise_iter_broken_links_2 ] ; then mkdir hirise_iter_broken_links_2 ; fi ; export_links.py -q $qual2 -i r2.hra -c $k -C 16 > hirise_iter_broken_links_2/$k.links
  } &
done
wait

for k in {0..15}; do
  {
   cat hirise_iter_broken_2.out | local_oo_opt.py -N 16 -a $k -l "hirise_iter_broken_links_2/*.links" -M datamodel.out > merge_links_tmp/refined_2.$k.out
  } &
done
wait

cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 7 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-7.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-11.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-14.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 6 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-6.out
cat merge_links_tmp/refined_2.10.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.10-11.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-13.out
cat merge_links_tmp/refined_2.14.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 14 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.14-14.out
cat merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.8-14.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.1.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 1 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-1.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-14.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 5 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-5.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 5 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-5.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-8.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-9.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 3 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-3.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-9.out
cat merge_links_tmp/refined_2.9.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.9-14.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 7 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-7.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-12.out
cat merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.8-11.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 5 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-5.out
cat merge_links_tmp/refined_2.11.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.11-13.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-11.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-13.out
cat merge_links_tmp/refined_2.10.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.10-13.out
cat merge_links_tmp/refined_2.9.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.9-9.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-11.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-15.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-13.out
cat merge_links_tmp/refined_2.14.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 14 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.14-15.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-8.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-9.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-9.out
cat merge_links_tmp/refined_2.12.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.12-12.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-8.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-13.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 3 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-3.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 5 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-5.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-9.out
cat merge_links_tmp/refined_2.12.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.12-13.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-11.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-11.out
cat merge_links_tmp/refined_2.10.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.10-10.out
cat merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.8-13.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-8.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-11.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 3 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-3.out
cat merge_links_tmp/refined_2.13.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.13-13.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-10.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-10.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-8.out
cat merge_links_tmp/refined_2.10.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.10-14.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 6 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-6.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 5 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-5.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 6 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-6.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-12.out
cat merge_links_tmp/refined_2.10.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.10-15.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-12.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-10.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-9.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-14.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 6 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-6.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 6 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-6.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-11.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 6 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-6.out
cat merge_links_tmp/refined_2.11.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.11-12.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 4 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-4.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-15.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-8.out
cat merge_links_tmp/refined_2.10.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 10 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.10-12.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 7 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-7.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 7 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-7.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 7 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-7.out
cat merge_links_tmp/refined_2.9.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.9-12.out
cat merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.8-8.out
cat merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 4 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.4-12.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-8.out
cat merge_links_tmp/refined_2.9.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.9-13.out
cat merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.8-10.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-15.out
cat merge_links_tmp/refined_2.12.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.12-15.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.1.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 1 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-1.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-13.out
cat merge_links_tmp/refined_2.13.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.13-14.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-12.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 2 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-2.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 4 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-4.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-13.out
cat merge_links_tmp/refined_2.15.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 15 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.15-15.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.0.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 0 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-0.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.5.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 5 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-5.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.3.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 3 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-3.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 4 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-4.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-13.out
cat merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.8-9.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-15.out
cat merge_links_tmp/refined_2.13.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 13 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.13-15.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-15.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-12.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 2 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-2.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 7 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-7.out
cat merge_links_tmp/refined_2.11.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.11-11.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-14.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 4 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-4.out
cat merge_links_tmp/refined_2.11.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.11-14.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-12.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-15.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.8.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 8 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-8.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.13.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 13 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-13.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-15.out
cat merge_links_tmp/refined_2.11.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 11 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.11-15.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 7 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-7.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-14.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-9.out
cat merge_links_tmp/refined_2.9.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.9-15.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-10.out
cat merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.8-12.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-14.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-15.out
cat merge_links_tmp/refined_2.9.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.9-10.out
cat merge_links_tmp/refined_2.12.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 12 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.12-14.out
cat merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 7 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.7-10.out
cat merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.7.out |p2edges.py |linker5.py --test_intercs -N 16 -a 5 -b 7 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.5-7.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-10.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-11.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.12.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 12 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-12.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.4.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 4 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-4.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.2.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 2 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-2.out
cat merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 6 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.6-10.out
cat merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.15.out |p2edges.py |linker5.py --test_intercs -N 16 -a 8 -b 15 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.8-15.out
cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 0 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.0-14.out
cat merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.9.out |p2edges.py |linker5.py --test_intercs -N 16 -a 1 -b 9 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.1-9.out
cat merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.10.out |p2edges.py |linker5.py --test_intercs -N 16 -a 3 -b 10 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.3-10.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.14.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 14 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-14.out
cat merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.6.out |p2edges.py |linker5.py --test_intercs -N 16 -a 2 -b 6 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.2-6.out
cat merge_links_tmp/refined_2.9.out merge_links_tmp/refined_2.11.out |p2edges.py |linker5.py --test_intercs -N 16 -a 9 -b 11 -L "hirise_iter_broken_links_2/*.links" -d -M datamodel.out > merge_links_tmp/links_2.9-11.out

dump_lengths.py -i r2.hra -o broken_lengths_2.out

cat merge_links_tmp/links_2.0-0.out merge_links_tmp/links_2.0-1.out merge_links_tmp/links_2.1-1.out merge_links_tmp/links_2.0-2.out merge_links_tmp/links_2.1-2.out merge_links_tmp/links_2.2-2.out merge_links_tmp/links_2.0-3.out merge_links_tmp/links_2.1-3.out merge_links_tmp/links_2.2-3.out merge_links_tmp/links_2.3-3.out merge_links_tmp/links_2.0-4.out merge_links_tmp/links_2.1-4.out merge_links_tmp/links_2.2-4.out merge_links_tmp/links_2.3-4.out merge_links_tmp/links_2.4-4.out merge_links_tmp/links_2.0-5.out merge_links_tmp/links_2.1-5.out merge_links_tmp/links_2.2-5.out merge_links_tmp/links_2.3-5.out merge_links_tmp/links_2.4-5.out merge_links_tmp/links_2.5-5.out merge_links_tmp/links_2.0-6.out merge_links_tmp/links_2.1-6.out merge_links_tmp/links_2.2-6.out merge_links_tmp/links_2.3-6.out merge_links_tmp/links_2.4-6.out merge_links_tmp/links_2.5-6.out merge_links_tmp/links_2.6-6.out merge_links_tmp/links_2.0-7.out merge_links_tmp/links_2.1-7.out merge_links_tmp/links_2.2-7.out merge_links_tmp/links_2.3-7.out merge_links_tmp/links_2.4-7.out merge_links_tmp/links_2.5-7.out merge_links_tmp/links_2.6-7.out merge_links_tmp/links_2.7-7.out merge_links_tmp/links_2.0-8.out merge_links_tmp/links_2.1-8.out merge_links_tmp/links_2.2-8.out merge_links_tmp/links_2.3-8.out merge_links_tmp/links_2.4-8.out merge_links_tmp/links_2.5-8.out merge_links_tmp/links_2.6-8.out merge_links_tmp/links_2.7-8.out merge_links_tmp/links_2.8-8.out merge_links_tmp/links_2.0-9.out merge_links_tmp/links_2.1-9.out merge_links_tmp/links_2.2-9.out merge_links_tmp/links_2.3-9.out merge_links_tmp/links_2.4-9.out merge_links_tmp/links_2.5-9.out merge_links_tmp/links_2.6-9.out merge_links_tmp/links_2.7-9.out merge_links_tmp/links_2.8-9.out merge_links_tmp/links_2.9-9.out merge_links_tmp/links_2.0-10.out merge_links_tmp/links_2.1-10.out merge_links_tmp/links_2.2-10.out merge_links_tmp/links_2.3-10.out merge_links_tmp/links_2.4-10.out merge_links_tmp/links_2.5-10.out merge_links_tmp/links_2.6-10.out merge_links_tmp/links_2.7-10.out merge_links_tmp/links_2.8-10.out merge_links_tmp/links_2.9-10.out merge_links_tmp/links_2.10-10.out merge_links_tmp/links_2.0-11.out merge_links_tmp/links_2.1-11.out merge_links_tmp/links_2.2-11.out merge_links_tmp/links_2.3-11.out merge_links_tmp/links_2.4-11.out merge_links_tmp/links_2.5-11.out merge_links_tmp/links_2.6-11.out merge_links_tmp/links_2.7-11.out merge_links_tmp/links_2.8-11.out merge_links_tmp/links_2.9-11.out merge_links_tmp/links_2.10-11.out merge_links_tmp/links_2.11-11.out merge_links_tmp/links_2.0-12.out merge_links_tmp/links_2.1-12.out merge_links_tmp/links_2.2-12.out merge_links_tmp/links_2.3-12.out merge_links_tmp/links_2.4-12.out merge_links_tmp/links_2.5-12.out merge_links_tmp/links_2.6-12.out merge_links_tmp/links_2.7-12.out merge_links_tmp/links_2.8-12.out merge_links_tmp/links_2.9-12.out merge_links_tmp/links_2.10-12.out merge_links_tmp/links_2.11-12.out merge_links_tmp/links_2.12-12.out merge_links_tmp/links_2.0-13.out merge_links_tmp/links_2.1-13.out merge_links_tmp/links_2.2-13.out merge_links_tmp/links_2.3-13.out merge_links_tmp/links_2.4-13.out merge_links_tmp/links_2.5-13.out merge_links_tmp/links_2.6-13.out merge_links_tmp/links_2.7-13.out merge_links_tmp/links_2.8-13.out merge_links_tmp/links_2.9-13.out merge_links_tmp/links_2.10-13.out merge_links_tmp/links_2.11-13.out merge_links_tmp/links_2.12-13.out merge_links_tmp/links_2.13-13.out merge_links_tmp/links_2.0-14.out merge_links_tmp/links_2.1-14.out merge_links_tmp/links_2.2-14.out merge_links_tmp/links_2.3-14.out merge_links_tmp/links_2.4-14.out merge_links_tmp/links_2.5-14.out merge_links_tmp/links_2.6-14.out merge_links_tmp/links_2.7-14.out merge_links_tmp/links_2.8-14.out merge_links_tmp/links_2.9-14.out merge_links_tmp/links_2.10-14.out merge_links_tmp/links_2.11-14.out merge_links_tmp/links_2.12-14.out merge_links_tmp/links_2.13-14.out merge_links_tmp/links_2.14-14.out merge_links_tmp/links_2.0-15.out merge_links_tmp/links_2.1-15.out merge_links_tmp/links_2.2-15.out merge_links_tmp/links_2.3-15.out merge_links_tmp/links_2.4-15.out merge_links_tmp/links_2.5-15.out merge_links_tmp/links_2.6-15.out merge_links_tmp/links_2.7-15.out merge_links_tmp/links_2.8-15.out merge_links_tmp/links_2.9-15.out merge_links_tmp/links_2.10-15.out merge_links_tmp/links_2.11-15.out merge_links_tmp/links_2.12-15.out merge_links_tmp/links_2.13-15.out merge_links_tmp/links_2.14-15.out merge_links_tmp/links_2.15-15.out | grep '^link score\|^interc:' > iter_links_2.out

cat iter_links_2.out | hiriseJoin.py -m 30.0 -s <( cat merge_links_tmp/refined_2.0.out merge_links_tmp/refined_2.1.out merge_links_tmp/refined_2.2.out merge_links_tmp/refined_2.3.out merge_links_tmp/refined_2.4.out merge_links_tmp/refined_2.5.out merge_links_tmp/refined_2.6.out merge_links_tmp/refined_2.7.out merge_links_tmp/refined_2.8.out merge_links_tmp/refined_2.9.out merge_links_tmp/refined_2.10.out merge_links_tmp/refined_2.11.out merge_links_tmp/refined_2.12.out merge_links_tmp/refined_2.13.out merge_links_tmp/refined_2.14.out merge_links_tmp/refined_2.15.out |p2edges.py ) -l broken_lengths_2.out > hirise_iter_3.out
set_layout.py -i assembly1.hra -o hirise_iter_3.hra -L hirise_iter_3.out

for k in {0..7};do
  {
   parallel_breaker.py -i hirise_iter_3.hra -o chicago_weak_segs_iter3_part$k.out -t 20 -T 30 -q $qual2 -j 2 -S $k,8 -H chicago_weak_segs_iter3_part$k.out.histogram > pb3-$k.out 2> pb3-$k.err 
  } &
done
wait

cat chicago_weak_segs_iter3_part0.out chicago_weak_segs_iter3_part1.out chicago_weak_segs_iter3_part2.out chicago_weak_segs_iter3_part3.out chicago_weak_segs_iter3_part4.out chicago_weak_segs_iter3_part5.out chicago_weak_segs_iter3_part6.out chicago_weak_segs_iter3_part7.out > chicago_weak_segs_iter3.out
break_playout.py -T 0.0 -t 0.0 -i hirise_iter_3.out -o hirise_iter_broken_3.out -b chicago_weak_segs_iter3.out > hirise_iter_broken_3.log
set_layout.py -i assembly1.hra -o hirise_iter_broken_3.hra -L hirise_iter_broken_3.out
dump_broken_contigs.py -i hirise_iter_broken_3.hra -f $INPUT_FASTA -o hirise_iter_broken_3.broken.fa
cat hirise_iter_broken_3.out | p2srf.py > hirise_iter_broken_3.srf

for k in {0..15};do
 {
  if [ $k -lt 10 ]
  then 
     cat hirise_iter_broken_3.out | place_gapper.py -b $SHOTGUN_BAM -f hirise_iter_broken_3.broken.fa -c 0$k -C 16 -K 51 | tee hirise_iter_broken_3.meraudierin.0$k.txt.inter | sort -k4,4 -k5,5 | format4merauder.py > hirise_iter_broken_3.meraudierin.0$k.txt
    merauder -A -c hirise_iter_broken_3.broken.fa -g hirise_iter_broken_3.meraudierin.0$k.txt -i 2000 -m 51 -P -s hirise_iter_broken_3.srf -D 3 > hirise_iter_broken_3.gapclose.0$k 2> hirise_iter_broken_3.gapclose.0$k.err
  else
    cat hirise_iter_broken_3.out | place_gapper.py -b $SHOTGUN_BAM -f hirise_iter_broken_3.broken.fa -c $k -C 16 -K 51 | tee hirise_iter_broken_3.meraudierin.$k.txt.inter | sort -k4,4 -k5,5 | format4merauder.py > hirise_iter_broken_3.meraudierin.$k.txt
    merauder -A -c hirise_iter_broken_3.broken.fa -g hirise_iter_broken_3.meraudierin.$k.txt -i 2000 -m 51 -P -s hirise_iter_broken_3.srf -D 3 > hirise_iter_broken_3.gapclose.$k 2> hirise_iter_broken_3.gapclose.$k.err
  fi
 } &
done
wait

cat hirise_iter_broken_3.gapclose.00 hirise_iter_broken_3.gapclose.01 hirise_iter_broken_3.gapclose.02 hirise_iter_broken_3.gapclose.03 hirise_iter_broken_3.gapclose.04 hirise_iter_broken_3.gapclose.05 hirise_iter_broken_3.gapclose.06 hirise_iter_broken_3.gapclose.07 hirise_iter_broken_3.gapclose.08 hirise_iter_broken_3.gapclose.09 hirise_iter_broken_3.gapclose.10 hirise_iter_broken_3.gapclose.11 hirise_iter_broken_3.gapclose.12 hirise_iter_broken_3.gapclose.13 hirise_iter_broken_3.gapclose.14 hirise_iter_broken_3.gapclose.15 > hirise_iter_broken_3.gapclose
cat hirise_iter_broken_3.out | grep '^p:' | p2fa2.py -l hirise_iter_broken_3.gapclosed.table --seed -1 -f $INPUT_FASTA -o /dev/stdout -g hirise_iter_broken_3.gapclose 2> hirise_iter_broken_3.gapclosed.fasta.out | add_short_contigs.py -b $INPUT_FASTA -o hirise_iter_broken_3.gapclosed.fasta

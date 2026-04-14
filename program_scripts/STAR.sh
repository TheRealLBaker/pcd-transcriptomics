#!/bin/bash

# jq is not a module in Iridis 6 atm so I've installed it in my conda env bedtools
# Load in JSON reader
source /iridisfs/i6software/conda/miniconda-py3/etc/profile.d/conda.sh
conda activate bedtools

# Check to see if both arguments are provided.
# Usage function
usage() {
    echo "Usage: $0 -i <sample_id> -b <batch_dir>"
    exit 1
}

# Initialize variables
sample_id=""
batch_dir=""

# Manual argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--sample)
            sample_id="$2"
            shift 2
            ;;
        -b|--batch)
            batch_dir="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option $1"
            usage
            ;;
    esac
done

# Ensure both required arguments are provided
if [[ -z "$sample_id" || -z "$batch_dir" ]]; then
    echo "Error: Missing required arguments."
    usage
fi

metadata="${batch_dir}/${sample_id}/metadata.json"
STAR_INDEX=$(jq -r '.STAR_index' "$metadata")
PROCESSED_1=$(jq -r '.processed_files."1"' "$metadata")
PROCESSED_2=$(jq -r '.processed_files."2"' "$metadata")
STAR_OUTPUT=$(jq -r '.STAR_output' "$metadata")
STAR_OUTPUT="${STAR_OUTPUT%/}"
rMATS_OUTPUT=$(jq -r '.rMATS_output' "$metadata")

# Debugging output to confirm that variables are being extracted correctly
echo "STAR_INDEX: $STAR_INDEX"
echo "PROCESSED_1: $PROCESSED_1"
echo "PROCESSED_2: $PROCESSED_2"
echo "STAR_OUTPUT: $STAR_OUTPUT"

# Ensure all variables were correctly extracted
if [[ -z "$STAR_INDEX" || -z "$PROCESSED_1" || -z "$PROCESSED_2" ]]; then
    echo "Error: One or more required fields are missing in metadata.json"
    exit 1
fi

cd $STAR_OUTPUT

# Create a temporary SLURM script
slurm_script="${batch_dir}/run_STAR_${sample_id}.slurm"

# When creating heredoc below, if the variable is passed in from the script above, can just use $ to get the literal string of the variable, may need to be exported in when running the script. However, if it is a variable created within the heredoc, need to do \$ to use as a variable.

cat <<EOT > "$slurm_script"
#!/bin/bash
#SBATCH -J STAR_${sample_id}  # Job name
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=19  # Adjust this as needed ***********
#SBATCH --mail-user=lb3e23@soton.ac.uk  # Your email address
#SBATCH --mail-type=ALL  # When to send email: BEGIN, END, FAIL, REQUEUE, ALL
#SBATCH --time=20:00:00  # Time limit

# Initialise the environment exactly like a login shell
source /etc/profile

# Load the STAR module - clear cache to prevent admin changes from affecting how the script works/ caveat is to remember that admin changes can affect tool versioning.
module --ignore_cache load STAR/2.7.11
# Load samtools
module --ignore_cache load samtools
# Load in JSON reader
source /iridisfs/i6software/conda/miniconda-py3/etc/profile.d/conda.sh
conda activate bedtools

# Verify what’s active
echo "Modules loaded:"
module list
echo "Active conda env:"
conda info --envs

# Debugging output for checking passed variables inside the SLURM script
echo "STAR_OUTPUT: $STAR_OUTPUT"
echo "STAR_INDEX: $STAR_INDEX"
echo "PROCESSED_1: $PROCESSED_1"
echo "PROCESSED_2: $PROCESSED_2"

# STAR command
STAR --genomeDir "$STAR_INDEX" \
--readFilesCommand zcat \
--readFilesIn "$PROCESSED_1" "$PROCESSED_2" \
--runThreadN 19 \
--twopassMode Basic \
--twopass1readsN -1 \
--outSAMmapqUnique 60 \
--outFilterType BySJout \
--outFilterMultimapNmax 20 \
--alignSJoverhangMin 8 \
--alignSJDBoverhangMin 3 \
--outFilterMismatchNmax 999 \
--outFilterMismatchNoverReadLmax 0.04 \
--alignIntronMin 20 \
--alignIntronMax 1000000 \
--limitSjdbInsertNsj 2000000 \
--alignMatesGapMax 1000000 \
--outFileNamePrefix "$STAR_OUTPUT/" \
--quantMode GeneCounts \
--outReadsUnmapped Fastx \
--outSAMtype BAM Unsorted 

## SamTools command
samtools sort "$STAR_OUTPUT/Aligned.out.bam" > "$STAR_OUTPUT/${sample_id}.sorted.bam"
samtools index "$STAR_OUTPUT/${sample_id}.sorted.bam"

# Remove intermdiate files
rm -rf "$STAR_OUTPUT/Unmapped.out.mate2" "$STAR_OUTPUT/Unmapped.out.mate1" "$STAR_OUTPUT/_STARgenome" "$STAR_OUTPUT/_STARpass1" "$STAR_OUTPUT/Aligned.out.bam"

## Update metadata.json
## Check for the existence of non-empty .sorted.bam, -s checks for non-empty
#SORTED_OUT=$(find "$STAR_OUTPUT" -type f -name "*.sorted.bam" | head -n 1)
#if [[ ! -f "\$SORTED_OUT" || ! -s "\$SORTED_OUT" ]]; then
#    echo "Error: STAR output BAM file is missing or empty for $sample_id: $SORTED_OUT" >&2
#    exit 1
#fi
#
## Remove the original unaligned BAM file if sorted BAM exists
#if [[ -f "$STAR_OUTPUT/${sample_id}.sorted.bam" && -s "$STAR_OUTPUT/${sample_id}.sorted.bam" ]]; then
#    rm "$STAR_OUTPUT/Aligned.out.bam"
#fi
#
#echo "\$SORTED_OUT"

# Update metadata.json with the sorted BAM path
jq --arg bam "\$SORTED_OUT" '.bam = \$bam' "$metadata" > "${batch_dir}/${sample_id}/metadata.tmp" && mv "${batch_dir}/${sample_id}/metadata.tmp" "$metadata"

EOT

# Submit the SLURM script and pass variables with --export
sbatch --export=sample_id="$sample_id",batch_dir="$batch_dir",STAR_OUTPUT="$STAR_OUTPUT",STAR_INDEX="$STAR_INDEX",PROCESSED_1="$PROCESSED_1",PROCESSED_2="$PROCESSED_2" "$slurm_script"

echo "SLURM job submitted: $slurm_script"




###### Debugging code below
# STAR command
#echo STAR --genomeDir "$STAR_INDEX" \
#--readFilesCommand zcat \
#--readFilesIn "$PROCESSED_1" "$PROCESSED_2" \
#--runThreadN 19 \
#--twopassMode Basic \
#--twopass1readsN -1 \
#--outSAMmapqUnique 60 \
#--outFilterType BySJout \
#--outFilterMultimapNmax 20 \
#--alignSJoverhangMin 8 \
#--alignSJDBoverhangMin 3 \
#--outFilterMismatchNmax 999 \
#--outFilterMismatchNoverReadLmax 0.04 \
#--alignIntronMin 20 \
#--alignIntronMax 1000000 \
#--limitSjdbInsertNsj 2000000 \
#--alignMatesGapMax 1000000 \
#--quantMode GeneCounts \
#--outReadsUnmapped Fastx \
#--outSAMtype BAM Unsorted 
#
### SamTools command
#echo samtools sort ./Aligned.out.bam > ./${sample_id}.sorted.bam
#echo samtools index ./${sample_id}.sorted.bam
#echo $STAR_OUTPUT

# Update metadata.json
# Check for the existence of non-empty .sorted.bam
#SORTED_OUT=$(find "$STAR_OUTPUT" -type f -name "*.sorted.bam" | head -n 1)
#if [[ ! -f "$SORTED_OUT" || ! -s "$SORTED_OUT" ]]; then
#    echo "Error: STAR output BAM file is missing or empty for $sample_id: $SORTED_OUT" >&2
#    exit 1
#fi
#echo $SORTED_OUT
#jq --arg bam "$SORTED_OUT" '.STAR_sorted_bam = $bam' "$metadata" > "${batch_dir}/${sample_id}/metadata.tmp" && mv "${batch_dir}/${sample_id}/metadata.tmp" "$metadata"











## Wait mechanism - wait until num of sorted.bam equates the num of directories in controlPath, ensure correct metadata creation for rMATS and MAJIQ
#controlsPath=$(jq -r '.controls.path' "$metadata")
## Get the expected number of control directories
#expected_count=$(find "$controlsPath" -mindepth 1 -maxdepth 1 -type d | wc -l)
## Function to wait until the number of .sorted.bam files matches expected count
#wait_for_controls() {
#    echo "Waiting for all control BAMs to be available..."
#
#    while true; do
#        # Count the number of .sorted.bam files found (including subdirectories)
#        current_count=$(find "$controlsPath" -type f -name "*.sorted.bam" | wc -l)
#
#        echo "Found $current_count of $expected_count expected BAM files."
#
#        # Check if we have all expected BAMs
#        if [[ $current_count -eq $expected_count ]]; then
#            echo "All control BAMs are now available!"
#            break
#        fi
#
#        sleep 30  # Wait for 30 seconds before checking again
#    done
#}
#wait_for_controls
#
#
#
## Create rMATS .txt file and update metadata.json
#if [[ ${#SORTED_OUT[@]} -gt 0 ]]; then
#    (IFS=,; echo "${SORTED_OUT[*]}") > "$rMATS_OUTPUT/${sample_id}.txt"
#else
#    echo "Warning: No sorted BAM files found at $STAR_OUTPUT" >&2
#    > "$rMATS_OUTPUT/${sample_id}.txt" # Create an empty file to avoid errors downstream
#fi
#jq --arg rMATS_path "$rMATS_OUTPUT/${sample_id}.txt" '.resource.rMATS.samplePath = $rMATS_path' "$metadata" > "${batch_dir}/${sample_id}/metadata.tmp" && mv "${batch_dir}/${sample_id}/metadata.tmp" "$metadata"
#
#
## Create majiq.config file and update metadata.json
## Get controls path and list of control's .sorted.bams ################ Need just the dir name, refer to previous configs
#controlsPath=$(jq -r '.controls.path' "$metadata")
## find array of sorted bams
#if [[ -n "$controlsPath" && -d "$controlsPath" ]]; then
#    mapfile -t controlsList < <(find "$controlsPath" -type f -name "*.sorted.bam")
#else
#    controlsList=()
#fi
## if list not empty (greater than 0), assign items from array to variable, IFS=,
## Extract directory paths from controlsList
#if [[ ${#controlsList[@]} -gt 0 ]]; then
#    mapfile -t controlsDirs < <(printf "%s\n" "${controlsList[@]}" | xargs -I {} dirname {})
#    all_bamdirs=$(IFS=,; echo "${controlsDirs[*]}")
#else
#    all_bamdirs=""
#fi
## Get the directory of the sorted bam - handles missing values
#SORTED_DIR=$(dirname "${SORTED_OUT:-}")
## Joining sample and controls paths via ,
#if [[ -n "$all_bamdirs" ]]; then
#    bamdirs="${SORTED_DIR},${all_bamdirs}"
#else
#    bamdirs="$SORTED_DIR"
#fi
#
## Extract basenames from controlsList, sort them, and create a comma-separated list
#if [[ ${#controlsList[@]} -gt 0 ]]; then
#    mapfile -t sorted_names < <(printf "%s\n" "${controlsList[@]}" | xargs -I {} basename {} | sed 's/\.bam$//' | sort)
#    IFS=,; control_names="${sorted_names[*]}"
#else
#    control_names=""
#fi
## Extract basename of sample and remove .bam extension
#SAMPLE_BASE=$(basename "${SORTED_OUT:-}" | sed 's/\.bam$//')
#majiq_config_file=$(jq -r '.MAJIQ_output' "$metadata")
#majiq_config_path="${majiq_config_file}/${sample_id}_majiqConfig.txt"
#{
#    echo "[info]"
#    echo "bamdirs=${bamdirs}"
#    echo "genome=hg38"
#    echo "strandness=reverse"
#    echo "[experiments]"
#    echo "Patient=${SAMPLE_BASE}"
#    echo "Controls=${control_names}"
#} > $majiq_config_path
#jq --arg majiq_config_path "$majiq_config_path" '.resource.MAJIQ.samplePath = $majiq_config_path' "$metadata" > "${batch_dir}/${sample_id}/metadata.tmp" && mv "${batch_dir}/${sample_id}/metadata.tmp" "$metadata"
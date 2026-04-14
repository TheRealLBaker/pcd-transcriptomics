#!/bin/bash

# Load in JSON reader (jq is in bedtools env)
source /iridisfs/i6software/conda/miniconda-py3/etc/profile.d/conda.sh
conda activate bedtools

usage() {
    echo "Usage: $0 -i <sample_id> -b <batch_dir>"
    exit 1
}

# Initialize variables
sample_id=""
batch_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--sample) sample_id="$2"; shift 2 ;;
        -b|--batch)  batch_dir="$2"; shift 2 ;;
        -h|--help)   usage ;;
        *) echo "Error: Unknown option $1"; usage ;;
    esac
done

if [[ -z "$sample_id" || -z "$batch_dir" ]]; then
    echo "Error: Missing required arguments."
    usage
fi

# Extract metadata values
metadata="${batch_dir}/${sample_id}/metadata.json"
STAR_OUTPUT=$(jq -r '.STAR_output' "$metadata")
STAR_OUTPUT="${STAR_OUTPUT%/}"
echo "STAR output: $STAR_OUTPUT"
output=$(jq -r '.PICARD_OUTPUT' "$metadata")


# Create a temporary SLURM script
slurm_script="${batch_dir}/run_fastqc_${sample_id}.slurm"

# We use <<'EOT' (quoted) so that $variables inside the script 
# are evaluated when the SLURM JOB runs, not when this wrapper runs.
cat <<'EOT' > "$slurm_script"
#!/bin/bash
#SBATCH -J FastQC_${sample_id}
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mail-user=lb3e23@soton.ac.uk
#SBATCH --mail-type=ALL
#SBATCH --time=40:00:00

# Load modules/env
source /iridisfs/i6software/conda/miniconda-py3/etc/profile.d/conda.sh
module load picard
module load R

# These variables are passed from the 'sbatch --export' command
mkdir -p "$output"
echo "Processing Sample: $sample_id"
echo "Output Directory: $output"

### File organisation
# 1. Clean up potential double slashes in the path
base_directory=$(echo "$STAR_OUTPUT" | sed 's/\/\//\//g')
sample=$sample_id

echo "Searching for BAM in: $base_directory"

# 2. Strict find: look for the sample ID and .bam extension
# We use -L in case there are symlinks and remove backslashes from $variables
bam_file=$(find "$base_directory" -maxdepth 1 -type f -name "${sample}.sorted.bam")

# 3. Validation Gate
if [[ -z "$bam_file" ]]; then
    echo "ERROR: Could not find ${sample}.sorted.bam in $base_directory"
    echo "Actual directory contents:"
    ls "$base_directory"
    exit 1
fi

## Picard CollectRNAseqMetrics
picard CollectRnaSeqMetrics \
I=$bam_file \
O=$output/${sample}.rnaseq_metrics \
CHART=$output/${sample}.rnaseq.pdf \
REF_FLAT="/iridisfs/pcd/resources/Genome_and_annotations/refFlat.txt" \
STRAND_SPECIFICITY=SECOND_READ_TRANSCRIPTION_STRAND \
RIBOSOMAL_INTERVALS="/iridisfs/scratch/lb3e23/iridis5_scratch_transfer/Resources/gencode.v44.rRNA.interval_list"
#*********** check https://gist.github.com/slowkow/b11c28796508f03cdf4b
#https://www.biostars.org/p/67079/
#https://slowkow.com/notes/ribosomal-rna/

## Picard CollectInsertSizeMetrics
picard CollectInsertSizeMetrics \
I=$bam_file \
O=$output/${sample}.insert_size_metrics \
H=$output/${sample}.insert_size_metrics.pdf \
M=0.5
EOT

# Submit and explicitly pass the variables to the compute node
sbatch --export=ALL,sample_id="$sample_id",output="$output",batch_dir="$batch_dir",STAR_OUTPUT="$STAR_OUTPUT" "$slurm_script"

echo "SLURM job submitted: $slurm_script"
#!/bin/bash

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

# Extract metadata values
metadata="${batch_dir}/${sample_id}/metadata.json"
STAR_OUTPUT=$(jq -r '.STAR_output' "$metadata")
STAR_OUTPUT="${STAR_OUTPUT%/}"
echo "STAR output: $STAR_OUTPUT"
HTSeq_OUTPUT=$(jq -r '.HTSeq_output' "$metadata")
GTF=$(jq -r '.resource.annotation.gtf' "$metadata")

# Navigate to HTSeq output directory
cd $HTSeq_OUTPUT

# Create a temporary SLURM script
slurm_script="${batch_dir}/run_HTSeq_${sample_id}.slurm"

cat <<EOT > "$slurm_script"
#!/bin/bash
#SBATCH -J HTSeq_${sample_id}     # Job name
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1 # Adjust this as needed ***********
#SBATCH --mail-user=lb3e23@soton.ac.uk  # Your email address
#SBATCH --mail-type=ALL           # When to send email: BEGIN, END, FAIL, REQUEUE, ALL
#SBATCH --time=30:00:00   # Time limit

# Activate conda environment that contains HTSeq
source /iridisfs/i6software/conda/miniconda-py3/etc/profile.d/conda.sh
conda activate HTSeq


### File organisation
sample=$sample_id
base_directory=$STAR_OUTPUT
echo "Base directory: \$base_directory"
if [[ -d "\$base_directory" ]]; then
    bam_file=\$(find "\$base_directory" -type f -name "\${sample}*.sorted.bam")
else
    bam_file=\$base_directory
fi

# Check if directory exists, if not, create it.
output_dir=$HTSeq_OUTPUT
mkdir -p "\${output_dir}"
echo "Output directory: \$output_dir"
echo "Sample: \$sample"

## HTSeq script
echo "BAM file: \$bam_file"
gtf=$GTF
htseq-count --format=bam --order=pos --stranded=reverse --max-reads-in-buffer=150000000 --mode=union -a=1 --type=exon \$bam_file \$gtf > "\${output_dir}/\${sample}.rawReadCounts.txt"

EOT

# Submit the SLURM script and pass variables with --export. This allows the variables set prior to the slurm script to be retained.
# This needs to be done because the slurm is in a different conda environment and the variables are therefore not passed through when running.
sbatch --export=sample_id="$sample_id",batch_dir="$batch_dir",STAR_OUTPUT="$STAR_OUTPUT",HTSeq_OUTPUT="$HTSeq_OUTPUT",GTF="$GTF" "$slurm_script"

echo "SLURM job submitted: $slurm_script"

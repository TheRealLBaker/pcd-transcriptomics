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
STAR_preprocessed_1=$(jq -r '.processed_files."1"' "$metadata")
STAR_preprocessed_2=$(jq -r '.processed_files."2"' "$metadata")
output=$(jq -r '.STAR_output' "$metadata")

echo "Found Files:"
echo "1: $STAR_preprocessed_1"
echo "2: $STAR_preprocessed_2"

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
#SBATCH --time=4:00:00

# Load modules/env
source /iridisfs/i6software/conda/miniconda-py3/etc/profile.d/conda.sh
module load fastqc

# These variables are passed from the 'sbatch --export' command
mkdir -p "$output"
echo "Processing Sample: $sample_id"
echo "Output Directory: $output"

fastqc "$STAR_preprocessed_1" --outdir="$output"
fastqc "$STAR_preprocessed_2" --outdir="$output"
EOT

# Submit and explicitly pass the variables to the compute node
sbatch --export=ALL,sample_id="$sample_id",output="$output",STAR_preprocessed_1="$STAR_preprocessed_1",STAR_preprocessed_2="$STAR_preprocessed_2" "$slurm_script"

echo "SLURM job submitted: $slurm_script"
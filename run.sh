#!/bin/bash

## If environment.yaml has been changed, the existing environment needs to be removed
## in order to re-generate the environment using:
#source ~/.bashrc; conda env remove -n workflow_lied_egypt_genome

mkdir -p log

echo "GENERATING AND ACTIVATING BIOCONDA WORKFLOW ENVIRONMENT..."
export PATH="$HOME/miniconda3/bin:$PATH"
if [ ! -d $HOME/miniconda3/envs/workflow_lied_egypt_genome ]; then
    conda env create -n workflow_lied_egypt_genome --file environment.yaml
fi
source activate workflow_lied_egypt_genome

echo "RUNNING SNAKEMAKE WORKFLOW..."
snakemake --rerun-incomplete -k -j 10 --resources io=4 --use-conda --jobname "{jobid}.{rulename}.sh" --cluster "sbatch --mem 16G --partition=longterm --time 1-00:00:00 -c 2 -o log/%j.{rule}.log" --printshellcmds gc_get_mapped_egyptref_reads_all # results/repeatmasker_comparison.txt vc_flagstat_all

source deactivate
conda list -n workflow_lied_egypt_genome --export > environment_versions.yaml

if ! command -v conda > /dev/null; then
  source /etc/profile.d/modules.sh
  module load miniforge
fi
# `conda run` activates the environment, which is what points Nextflow at its own Java.
INSTALLED=$(conda run -p "$NEXTFLOW_ENVIRONMENT" nextflow -version 2> /dev/null || true)
if grep -q "version ${NEXTFLOW_VERSION} " <<< "$INSTALLED"; then
  echo "Nextflow ${NEXTFLOW_VERSION} is already in $NEXTFLOW_ENVIRONMENT."
else
  if [ -d "$NEXTFLOW_ENVIRONMENT/conda-meta" ]; then
    conda install -y -p "$NEXTFLOW_ENVIRONMENT" -c conda-forge -c bioconda --override-channels "nextflow=${NEXTFLOW_VERSION}" python pip
  else
    conda create -y -p "$NEXTFLOW_ENVIRONMENT" -c conda-forge -c bioconda --override-channels "nextflow=${NEXTFLOW_VERSION}" python pip
  fi
  # Each capsule upgrades the DANDI CLI itself before uploading.
  "$NEXTFLOW_ENVIRONMENT/bin/pip" install dandi
fi
conda run -p "$NEXTFLOW_ENVIRONMENT" nextflow -version
conda run -p "$NEXTFLOW_ENVIRONMENT" nextflow plugin install "$NF_SCHEMA_PLUGIN"

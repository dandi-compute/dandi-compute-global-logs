if "$DATALAD_ENVIRONMENT/bin/datalad" --version 2> /dev/null && "$DATALAD_ENVIRONMENT/bin/con-duct" run --help > /dev/null 2>&1; then
  echo "DataLad and con-duct are already in $DATALAD_ENVIRONMENT."
  exit 0
fi
if ! command -v conda > /dev/null; then
  source /etc/profile.d/modules.sh
  module load miniforge
fi
if [ -d "$DATALAD_ENVIRONMENT/conda-meta" ]; then
  conda install -y -p "$DATALAD_ENVIRONMENT" -c conda-forge --override-channels datalad "con-duct>=0.17"
else
  conda create -y -p "$DATALAD_ENVIRONMENT" -c conda-forge --override-channels datalad "con-duct>=0.17"
fi
"$DATALAD_ENVIRONMENT/bin/datalad" --version
"$DATALAD_ENVIRONMENT/bin/con-duct" --version

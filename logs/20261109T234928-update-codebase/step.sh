for directory in $DIRECTORIES; do
  if [ "$directory" = simple-s3-backup ]; then
    # Into the backup jobs' own environment, not the runner's.
    "$BACKUP_ENVIRONMENT/bin/pip" install -e "$BACKUP_CHECKOUT"
  elif [ -f "./$directory/pyproject.toml" ] || [ -f "./$directory/setup.py" ]; then
    pip install -e "./$directory/"
  else
    echo "No installable Python package found in ./$directory/; skipping reinstall."
  fi
done

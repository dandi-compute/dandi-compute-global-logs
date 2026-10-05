for directory in $DIRECTORIES; do
  if [ -f "./$directory/pyproject.toml" ] || [ -f "./$directory/setup.py" ]; then
    pip install -e "./$directory/"
  else
    echo "No installable Python package found in ./$directory/; skipping reinstall."
  fi
done

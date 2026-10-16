for directory in $DIRECTORIES; do
  echo "Pulling ./$directory/"
  git -C "./$directory/" fetch --tags origin
  # A detached checkout (aind-ephys-pipeline sits on whichever tag the last job checked out)
  # has no upstream to reset to. Each job checks out its own tag, so fetching is enough.
  if git -C "./$directory/" symbolic-ref -q HEAD > /dev/null; then
    git -C "./$directory/" reset --hard "@{u}"
  else
    echo "./$directory/ is on a detached HEAD; fetched new tags without resetting."
  fi
  if [ -d "./$directory/launcher" ]; then
    find "./$directory/launcher/" -maxdepth 1 -type f ! -name "crontab" -exec chmod +x {} +
  fi
done

for directory in $DIRECTORIES; do
  if [ "$directory" = simple-s3-backup ]; then
    # The backup jobs run whatever this checkout holds, so it is always put on main, even
    # when someone checked out another branch there by hand. That branch stays, unchanged.
    # From June to November 2026 an unmerged branch checked out here stopped the blob
    # backup without anyone knowing.
    echo "Putting $BACKUP_CHECKOUT on main"
    git -C "$BACKUP_CHECKOUT" fetch --prune origin
    previous=$(git -C "$BACKUP_CHECKOUT" rev-parse --abbrev-ref HEAD)
    git -C "$BACKUP_CHECKOUT" checkout --force -B main origin/main
    echo "Was on ${previous}; now on main at $(git -C "$BACKUP_CHECKOUT" log -1 --format='%h %s')."
    continue
  fi
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

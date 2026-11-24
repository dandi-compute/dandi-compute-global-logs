PROCESS_ARGS=(jobs dispatch --base /orcd/data/dandi/001/dandi-compute)

if [ "false" = "true" ]; then
  PROCESS_ARGS+=(--test)
fi

echo "Running: dandicompute ${PROCESS_ARGS[*]}"
flock -n ./flocks/process_queue.lock dandicompute "${PROCESS_ARGS[@]}"

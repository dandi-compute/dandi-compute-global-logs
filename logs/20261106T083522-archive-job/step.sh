if [ "$STATUS" = "all" ] && [ "$PIPELINE" = "all" ]; then
  if [ -z "$CAPSULE_PATH" ]; then
    echo "::error::Provide a job capsule \`path\`, or choose a \`status\` and/or \`pipeline\` to archive."
    exit 1
  fi
  dandicompute archive add --job "$CAPSULE_PATH" --base /orcd/data/dandi/001/dandi-compute
else
  if [ -n "$CAPSULE_PATH" ]; then
    echo "::error::\`path\` must be empty when archiving by \`status\` ($STATUS) or \`pipeline\` ($PIPELINE)."
    exit 1
  fi
  FILTERS=()
  if [ "$STATUS" != "all" ]; then
    FILTERS+=(--status "$STATUS")
  fi
  if [ "$PIPELINE" != "all" ]; then
    FILTERS+=(--pipeline "$PIPELINE")
  fi
  dandicompute archive add "${FILTERS[@]}" --base /orcd/data/dandi/001/dandi-compute
fi

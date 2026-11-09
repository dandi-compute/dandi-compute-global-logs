if [ "$STATUS" = "all" ] && [ "$PIPELINE" = "all" ]; then
  if [ -z "$CAPSULE_PATH" ]; then
    echo "::error::Provide a job capsule \`path\`, or choose a \`status\` and/or \`pipeline\` to archive."
    exit 1
  fi
  ARGS=(--job "$CAPSULE_PATH")
else
  if [ -n "$CAPSULE_PATH" ]; then
    echo "::error::\`path\` must be empty when archiving by \`status\` ($STATUS) or \`pipeline\` ($PIPELINE)."
    exit 1
  fi
  ARGS=()
  if [ "$STATUS" != "all" ]; then
    ARGS+=(--status "$STATUS")
  fi
  if [ "$PIPELINE" != "all" ]; then
    ARGS+=(--pipeline "$PIPELINE")
  fi
fi
# The command logs to stderr and keeps the output of its `dandi` calls to itself, so its
# stdout is only the closing report of what was archived.
dandicompute archive add "${ARGS[@]}" --base /orcd/data/dandi/001/dandi-compute | tee "$RUNNER_TEMP/archive.txt"
{
  echo "### Archived to the failed runs archive (001873)"
  echo '```'
  head -c 900000 "$RUNNER_TEMP/archive.txt"
  if [ "$(wc -c < "$RUNNER_TEMP/archive.txt")" -gt 900000 ]; then
    echo
    echo "... truncated to fit the 1 MB summary limit; the step log has the full list."
  fi
  echo '```'
} >> "$GITHUB_STEP_SUMMARY"

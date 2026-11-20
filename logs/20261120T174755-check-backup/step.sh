# sacct prints times in the cluster's own time zone, which date uses here too, so the
# two compare as text.
since=$(date -d "${WINDOW_HOURS} hours ago" '+%Y-%m-%dT%H:%M:%S')
# Twice the window, so a job submitted before it that ended inside it is listed too.
listed_from=$(date -d "$((2 * WINDOW_HOURS)) hours ago" '+%Y-%m-%dT%H:%M:%S')
if ! records=$(sacct --user "$(id -un)" --allocations --noheader --parsable2 \
    --starttime "$listed_from" --name "${JOBS// /,}" \
    --format JobID,JobName,Submit,End,State,ExitCode,Elapsed); then
  echo "::error title=sacct failed::Could not list the backup jobs with sacct, so whether they ran is unknown."
  exit 1
fi

redact() {
  if [ -f "$REDACT_SCRIPT" ]; then sed -E -f "$REDACT_SCRIPT"; else cat; fi
}
# The rows whose state is one of the given ones, or none of them with `!`. sacct writes
# a cancellation as "CANCELLED by UID", so only the state's first word is compared.
rows_in_state() {
  awk -F'|' -v pattern="^($2)\$" -v negate="${3:-}" \
    '$0 != "" { split($5, state, " "); if ((state[1] ~ pattern) != (negate == "!")) print }' <<< "$1"
}
# The first five rows, one task per line.
describe() {
  awk -F'|' 'NR <= 5 { printf "  %s %s (exit %s after %s)\n", $1, $5, $6, $7 }' <<< "$1"
}
FAILED_STATES='FAILED|OUT_OF_MEMORY|NODE_FAIL|BOOT_FAIL|DEADLINE'

report=$(mktemp)
mismatches=$(mktemp)
failed=0
# Whether anything failed other than tasks that found checksum mismatches.
other_failure=0
mismatch_count=0
for job in $JOBS; do
  # One row per job, or per task of an array job: JobID|JobName|Submit|End|State|ExitCode|Elapsed.
  # A task still running or pending has no End yet.
  rows=$(awk -F'|' -v job="$job" '$2 == job' <<< "$records")
  submitted=$(awk -F'|' -v since="$since" '$3 >= since' <<< "$rows" | grep -c . || true)
  ended=$(awk -F'|' -v since="$since" '$4 ~ /^[0-9]/ && $4 >= since' <<< "$rows")
  completed=$(rows_in_state "$ended" COMPLETED | grep -c . || true)
  failures=$(rows_in_state "$ended" "$FAILED_STATES")
  mismatch_tasks=""
  if [ "$job" = "$CHECKSUM_JOB" ]; then
    # FAILED with the exit code of a checksum mismatch, or not.
    mismatch_tasks=$(awk -F'|' -v code="$CHECKSUM_MISMATCH_EXIT" \
      '{ split($5, state, " ") } $0 != "" && state[1] == "FAILED" && $6 == code' <<< "$failures")
    failures=$(awk -F'|' -v code="$CHECKSUM_MISMATCH_EXIT" \
      '{ split($5, state, " ") } $0 != "" && !(state[1] == "FAILED" && $6 == code)' <<< "$failures")
  fi
  failed_count=$(grep -c . <<< "$failures" || true)
  mismatch_task_count=$(grep -c . <<< "$mismatch_tasks" || true)
  others=$(rows_in_state "$ended" "COMPLETED|$FAILED_STATES" !)
  other_count=$(grep -c . <<< "$others" || true)
  in_progress=$(awk -F'|' '$0 != "" && $4 !~ /^[0-9]/' <<< "$rows" | grep -c . || true)

  if [ "$submitted" -eq 0 ] && [ -z "$ended" ]; then
    failed=1
    other_failure=1
    echo "::error title=${job} not submitted::No ${job} job was submitted in the last ${WINDOW_HOURS} hours."
    {
      echo "${job}: no job was submitted in the last ${WINDOW_HOURS} hours."
      if [ "$in_progress" -gt 0 ]; then
        echo "  An earlier one is still pending or running (${in_progress} in sacct), and launcher/backup.sh"
        echo "  submits no other while it is. squeue shows why it has not ended."
      fi
      echo "  The crontab submits it through launcher/backup.sh, which records each submission in the"
      echo "  global logs under logs/. Check that the crontab is installed and what the last submission printed."
    } >> "$report"
    continue
  fi

  mismatch_summary=""
  if [ "$job" = "$CHECKSUM_JOB" ]; then
    mismatch_summary=", ${mismatch_task_count} found checksum mismatches"
  fi
  echo "${job}: ${completed} completed${mismatch_summary}, ${failed_count} failed, ${other_count} ended otherwise in the last ${WINDOW_HOURS} hours; ${in_progress} still pending or running." >> "$report"
  if [ "$mismatch_task_count" -gt 0 ]; then
    failed=1
    # Every blob each of those tasks deleted, once, from its [MISMATCH DELETED] lines:
    # "[MISMATCH DELETED] <key>: <reason>; the next blob backup copies it again".
    task_mismatches=$(mktemp)
    while read -r job_id; do
      log_file="${LOG_DIRECTORY}/${job}-${job_id}.log"
      if [ -r "$log_file" ]; then
        grep -a '^\[MISMATCH DELETED\] ' "$log_file" | redact \
          | sed -E 's/^\[MISMATCH DELETED\] //; s/; the next blob backup copies it again$//' >> "$task_mismatches" || true
      else
        echo "(task ${job_id} exited ${CHECKSUM_MISMATCH_EXIT}, but its log ${log_file} is not there)" >> "$task_mismatches"
      fi
    done < <(awk -F'|' '{ print $1 }' <<< "$mismatch_tasks")
    awk '!seen[$0]++' "$task_mismatches" >> "$mismatches"
    rm -f "$task_mismatches"
  fi
  if [ "$other_count" -gt 0 ]; then
    # A timeout or preemption on mit_preemptable is not a failure of the backup itself;
    # Check mirror growth notices if it keeps the mirror from growing.
    echo "::warning title=${job} ended early::${other_count} of its tasks timed out, were preempted or were cancelled in the last ${WINDOW_HOURS} hours."
    describe "$others" >> "$report"
  fi
  if [ "$failed_count" -gt 0 ]; then
    failed=1
    other_failure=1
    echo "::error title=${job} failed::${failed_count} of its tasks failed in the last ${WINDOW_HOURS} hours."
    describe "$failures" >> "$report"
    if [ "$job" = "$PLACEMENT_JOB" ]; then
      # verify-blobs exits 1 on a placement problem, as it does on any other failure (a
      # failed conda activate, an unreadable partitions.json, the lock held), so the note
      # is added only when a failed task's log has the [MISPLACED] or [MISSING] lines
      # that verify_dandi_blobs prints for a misplaced or missing head.
      placement_problem=0
      while read -r job_id; do
        log_file="${LOG_DIRECTORY}/${job}-${job_id}.log"
        if [ -r "$log_file" ] && grep -aqE '^\[(MISPLACED|MISSING)\] head ' "$log_file"; then
          placement_problem=1
        fi
      done < <(awk -F'|' '{ print $1 }' <<< "$failures")
      if [ "$placement_problem" -eq 1 ]; then
        {
          echo "  A blob head is on a partition that simple-s3-backup's partitions.json does not assign it to,"
          echo "  or missing from the one it does (the [MISPLACED] and [MISSING] lines of the log name which)."
          echo "  Nothing was deleted. The blob backup fills a missing head. The Cleanup misplaced blobs"
          echo "  workflow (s3backup dandi cleanup-misplaced-blobs) lists the copies left elsewhere in a dry"
          echo "  run, and with apply checked deletes those the assigned partition holds completely:"
          echo "  https://github.com/dandi-compute/dandi-compute-runner/actions/workflows/cleanup-misplaced-blobs.yml"
        } >> "$report"
      else
        echo "  Its log names no misplaced or missing blob head, so the check itself failed to run; see the end of its log." >> "$report"
      fi
    fi
    if [ "$failed_count" -gt 5 ]; then
      echo "  ... and $((failed_count - 5)) more" >> "$report"
    fi
    while read -r job_id; do
      log_file="${LOG_DIRECTORY}/${job}-${job_id}.log"
      echo "  End of ${log_file}:" >> "$report"
      if [ -r "$log_file" ]; then
        tail -n "$LOG_LINES" "$log_file" | redact | sed 's/^/    | /' >> "$report"
      else
        echo "    (not there; jobs submitted before launcher/backup.sh sent their output to /dev/null)" >> "$report"
      fi
    done < <(awk -F'|' -v shown="$LOGS_SHOWN" 'NR <= shown { print $1 }' <<< "$failures")
  fi
done

mismatch_count=$(grep -c . "$mismatches" || true)
shown_mismatches=$(mktemp)
if [ "$mismatch_count" -gt 0 ]; then
  echo "::error title=Checksum mismatch::${mismatch_count} mirrored blobs did not match the bucket; their copies were deleted for the next blob backup to copy again."
  head -n "$MISMATCHES_SHOWN" "$mismatches" | sed 's/^/  /' > "$shown_mismatches"
  if [ "$mismatch_count" -gt "$MISMATCHES_SHOWN" ]; then
    echo "  ... and $((mismatch_count - MISMATCHES_SHOWN)) more" >> "$shown_mismatches"
  fi
  {
    echo "Checksum mismatches: ${mismatch_count} mirrored blobs did not match the bucket, and their copies were deleted for the next blob backup to copy again:"
    cat "$shown_mismatches"
  } >> "$report"
fi

cat "$report"
{
  echo "### Backup jobs of the last ${WINDOW_HOURS} hours"
  echo
  echo '```'
  cat "$report"
  echo '```'
} >> "$GITHUB_STEP_SUMMARY"
delimiter="REPORT_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
{
  echo "report<<${delimiter}"
  cat "$report"
  echo "${delimiter}"
  echo "mismatches<<${delimiter}"
  cat "$shown_mismatches"
  echo "${delimiter}"
  if [ "$mismatch_count" -gt 0 ] && [ "$other_failure" -eq 0 ]; then
    echo "only_checksum_mismatches=true"
  else
    echo "only_checksum_mismatches=false"
  fi
} >> "$GITHUB_OUTPUT"
exit "$failed"

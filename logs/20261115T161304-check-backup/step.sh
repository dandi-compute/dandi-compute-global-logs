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
failed=0
for job in $JOBS; do
  # One row per job, or per task of an array job: JobID|JobName|Submit|End|State|ExitCode|Elapsed.
  # A task still running or pending has no End yet.
  rows=$(awk -F'|' -v job="$job" '$2 == job' <<< "$records")
  submitted=$(awk -F'|' -v since="$since" '$3 >= since' <<< "$rows" | grep -c . || true)
  ended=$(awk -F'|' -v since="$since" '$4 ~ /^[0-9]/ && $4 >= since' <<< "$rows")
  completed=$(rows_in_state "$ended" COMPLETED | grep -c . || true)
  failures=$(rows_in_state "$ended" "$FAILED_STATES")
  failed_count=$(grep -c . <<< "$failures" || true)
  others=$(rows_in_state "$ended" "COMPLETED|$FAILED_STATES" !)
  other_count=$(grep -c . <<< "$others" || true)
  in_progress=$(awk -F'|' '$0 != "" && $4 !~ /^[0-9]/' <<< "$rows" | grep -c . || true)

  if [ "$submitted" -eq 0 ] && [ -z "$ended" ]; then
    failed=1
    echo "::error title=${job} not submitted::No ${job} job was submitted in the last ${WINDOW_HOURS} hours."
    {
      echo "${job}: no job was submitted in the last ${WINDOW_HOURS} hours."
      echo "  The crontab submits it through launcher/backup.sh, which records each submission in the"
      echo "  global logs under logs/. Check that the crontab is installed and what the last submission printed."
    } >> "$report"
    continue
  fi

  echo "${job}: ${completed} completed, ${failed_count} failed, ${other_count} ended otherwise in the last ${WINDOW_HOURS} hours; ${in_progress} still pending or running." >> "$report"
  if [ "$other_count" -gt 0 ]; then
    # A timeout or preemption on mit_preemptable is not a failure of the backup itself;
    # Check mirror growth notices if it keeps the mirror from growing.
    echo "::warning title=${job} ended early::${other_count} of its tasks timed out, were preempted or were cancelled in the last ${WINDOW_HOURS} hours."
    describe "$others" >> "$report"
  fi
  if [ "$failed_count" -gt 0 ]; then
    failed=1
    echo "::error title=${job} failed::${failed_count} of its tasks failed in the last ${WINDOW_HOURS} hours."
    describe "$failures" >> "$report"
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
} >> "$GITHUB_OUTPUT"
exit "$failed"

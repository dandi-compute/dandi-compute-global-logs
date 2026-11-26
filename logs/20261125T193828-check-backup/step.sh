write_report() {
  echo "$1"
  {
    echo "### Blob mirror growth"
    echo
    echo '```'
    echo "$1"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
  delimiter="REPORT_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  printf 'report<<%s\n%s\n%s\n' "$delimiter" "$1" "$delimiter" >> "$GITHUB_OUTPUT"
}

# The logs of the blob backup tasks that wrote in the last GROWTH_DAYS days.
logs=()
if [ -d "$LOG_DIRECTORY" ]; then
  mapfile -t logs < <(find "$LOG_DIRECTORY" -maxdepth 1 -type f -name "${BLOB_JOB}-*_*.log" \
    -mmin -"$((GROWTH_DAYS * 24 * 60))" | sort -V)
fi
# s5cmd prints "cp s3://dandiarchive/blobs/<key> <local path>" for each object it copies (and
# nothing for one it skips), and simple-s3-backup's blob backup sends that to the task's log.
# One record of the totals, "C <copies> <distinct keys> <array jobs>", and one per key copied by
# more than one array job, so on more than one day: "R <array jobs> <key> <their IDs>".
tallies=""
if [ "${#logs[@]}" -gt 0 ]; then
  tallies=$(awk '
    FNR == 1 {
      array = FILENAME
      sub(/.*\//, "", array); sub(/_[0-9]+\.log$/, "", array); sub(/.*-/, "", array)
      if (!(array in arrays)) { arrays[array] = 1; array_count++ }
    }
    $1 == "cp" && index($2, "s3://dandiarchive/blobs/") == 1 {
      key = substr($2, length("s3://dandiarchive/") + 1)
      copies++
      if (!(key in days)) distinct++
      if (!((key, array) in seen)) {
        seen[key, array] = 1
        days[key]++
        which[key] = which[key] (which[key] == "" ? "" : ",") array
      }
    }
    END {
      printf "C %d %d %d\n", copies, distinct, array_count
      for (key in days) if (days[key] > 1) printf "R %d %s %s\n", days[key], key, which[key]
    }' "${logs[@]}")
fi
read -r _ copies distinct array_count <<< "$(grep '^C ' <<< "$tallies" || echo "C 0 0 0")"
repeats=$(grep '^R ' <<< "$tallies" | sort -k2,2nr -k3,3 || true)
repeat_count=$(grep -c . <<< "$repeats" || true)

if [ "${#logs[@]}" -eq 0 ]; then
  report="No ${BLOB_JOB} log in ${LOG_DIRECTORY} was written in the last ${GROWTH_DAYS} days, so no blob was copied."
else
  report="The ${#logs[@]} task logs of the ${array_count} ${BLOB_JOB} array jobs that wrote in the last ${GROWTH_DAYS} days show ${copies} blobs copied, ${distinct} distinct."
fi
if [ -n "$REMOTE_NOW" ]; then
  gained_remotely=$((REMOTE_NOW - REMOTE_THEN))
  report="${report}
Between ${THEN_DATE} and ${NOW_DATE} the bucket went from ${REMOTE_THEN} to ${REMOTE_NOW} blobs (${gained_remotely})."
else
  gained_remotely=""
  report="${report}
How many blobs the bucket gained is unknown: ${BUCKET_NOTE:-Read bucket growth reported nothing; see the run.}"
fi

if [ "$repeat_count" -gt 0 ]; then
  # A blob copied again on another day had a local copy of the wrong size, or none: verify-checksums
  # deletes a copy that does not match the bucket, so one it wrongly flags is deleted and copied every day.
  echo "::warning title=Blobs copied on several days::${repeat_count} blobs were copied by more than one daily blob backup in the last ${GROWTH_DAYS} days."
  report="${report}
${repeat_count} of those blobs were copied by more than one daily blob backup, which a copy deleted every day
(by DANDI-Verify-Checksums, see the checksum mismatch ledger) or a copy that never keeps its size would explain:
$(head -n "$REPEATS_SHOWN" <<< "$repeats" | awk '{ printf "  %s: %d days (array jobs %s)\n", $3, $2, $4 }')"
  if [ "$repeat_count" -gt "$REPEATS_SHOWN" ]; then
    report="${report}
  ... and $((repeat_count - REPEATS_SHOWN)) more"
  fi
fi

if [ "$copies" -eq 0 ] && [ "${gained_remotely:-1}" -gt 0 ]; then
  if [ -n "$gained_remotely" ]; then
    echo "::error title=Blob mirror not growing::No blob was copied in ${GROWTH_DAYS} days while the bucket gained ${gained_remotely}."
  else
    echo "::error title=Blob mirror not growing::No blob was copied in ${GROWTH_DAYS} days, and whether the bucket gained any is unknown."
  fi
  if [ "${#logs[@]}" -gt 0 ]; then
    report="${report}
If the logs have no \"cp s3://\" line at all, the simple-s3-backup checkout at /orcd/data/dandi/001/backup/simple-s3-backup
may predate https://github.com/dandi/simple-s3-backup/pull/57, from which s5cmd's output reaches them."
  fi
  write_report "The blob mirror has not grown in ${GROWTH_DAYS} days. ${report}"
  exit 1
fi
write_report "$report"

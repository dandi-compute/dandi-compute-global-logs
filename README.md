# DANDI Compute (Global logs)

Global logs of runtime activity for DANDI Compute: every scheduled task, workflow step and
monitor snapshot that runs on MIT Engaging. The logs of individual job capsules are not here;
they stay with each capsule and are uploaded to DANDI with it.

## Layout

Each day's records live on their own branch, named for the date (`YYYY-MM-DD`). `main` holds
nothing but this README and the dataset configuration, so old days can be deleted as branches
without touching its history.

Every branch is a [DataLad](https://www.datalad.org/) dataset (without git-annex, since
everything recorded is small text). Each record is a `datalad run` commit, so its message holds
the exact command, the directory it ran in and its exit status, and `datalad rerun` can repeat
it.

```
logs/{YYYYMMDDTHHMMSS}-{action}/     one scheduled task or workflow step
monitor/{YYYYMMDDTHHMMSS}-squeue/    a squeue snapshot, every 5 minutes
```

Each record directory holds:

| File | What |
|---|---|
| `stdout`, `stderr` | The command's output. |
| `exit_status` | The command's exit status. |
| `info.json`, `usage.jsonl` | [duct](https://github.com/con/duct)'s summary and resource samples, when duct is available. |
| `record.log` | Anything that went wrong while recording or delivering this record. |
| `step.sh` | For a GitHub Actions step, the script the step ran. |

## How records are made

Everything goes through
[`launcher/record.sh`](https://github.com/dandi-compute/dandi-compute-runner/blob/main/launcher/record.sh)
in dandi-compute-runner:

```bash
record.sh logs dispatch -- bash .../launcher/tasks/dispatch.sh
```

It runs the command under `datalad run` (inside duct) in a throwaway clone. It then moves that
commit onto the day's branch in the shared checkout at
`/orcd/data/dandi/001/dandi-compute/dandi-compute-global-logs` and pushes it here. The shared
checkout is locked only for that last step, so a long task never holds up the others.

Recording is built never to lose a record and never to stop the work it records:

- Without DataLad, the command still runs and its output is committed with plain git.
- When the shared checkout is busy or broken, the record is pushed here straight from the
  throwaway clone.
- When GitHub cannot be reached, the record is kept under `untracked/unpushed/` in the shared
  checkout and committed with the next record that gets through.

The shared checkout is managed by `record.sh`, which resets it before each delivery, so it
should not be edited by hand.

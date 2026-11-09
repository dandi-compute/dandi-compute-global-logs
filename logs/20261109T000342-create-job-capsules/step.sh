# One call per configured pipeline, so each gets its own limit and none can starve another.
# Creation gives each asset a capsule for every parameter set of the pipeline (one per
# spike sorter for aind+ephys) before moving to the next asset, so the limit is scaled by
# the parameter set count to keep it a limit on assets.
PIPELINES=$(python -c "from dandi_compute_code.queue import PipelineQueue; print(*PipelineQueue.load_pipeline_config()['pipelines'])")
for pipeline in $PIPELINES; do
  PARAMS_COUNT=$(python -c "from dandi_compute_code.queue import PipelineQueue; print(len(PipelineQueue.load_pipeline_config()['pipelines']['$pipeline'].get('params', [])))")
  LIMIT=$(( 5 * ${PARAMS_COUNT:-1} ))
  dandicompute jobs create --base /orcd/data/dandi/001/dandi-compute --pipeline "$pipeline" --limit "$LIMIT"
done

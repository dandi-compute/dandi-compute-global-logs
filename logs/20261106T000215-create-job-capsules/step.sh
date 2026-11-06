# One call per configured pipeline, so each gets its own limit and none can starve another.
PIPELINES=$(python -c "from dandi_compute_code.queue import PipelineQueue; print(*PipelineQueue.load_pipeline_config()['pipelines'])")
for pipeline in $PIPELINES; do
  dandicompute jobs create --base /orcd/data/dandi/001/dandi-compute --pipeline "$pipeline" --limit 5
done

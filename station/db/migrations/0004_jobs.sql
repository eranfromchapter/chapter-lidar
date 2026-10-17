-- Up Migration
-- Work queue for the station worker (checks and publish jobs), claimed with
-- SELECT ... FOR UPDATE SKIP LOCKED:
--
--   UPDATE jobs SET status = 'running', locked_at = now(), locked_by = $1, attempts = attempts + 1
--   WHERE job_id = (
--     SELECT job_id FROM jobs
--     WHERE status = 'queued' AND run_after <= now()
--     ORDER BY run_after, created_at
--     FOR UPDATE SKIP LOCKED
--     LIMIT 1)
--   RETURNING *;
--
-- At most one queued or running job exists per package and job type.

CREATE TABLE jobs (
  job_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CONSTRAINT jobs_type_valid CHECK (type IN ('checks', 'publish')),
  package_id uuid NOT NULL REFERENCES packages (package_id),
  status text NOT NULL DEFAULT 'queued'
    CONSTRAINT jobs_status_valid CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
  attempts integer NOT NULL DEFAULT 0 CONSTRAINT jobs_attempts_nonnegative CHECK (attempts >= 0),
  max_attempts integer NOT NULL DEFAULT 5
    CONSTRAINT jobs_max_attempts_positive CHECK (max_attempts >= 1),
  -- Not claimed before this time (retry backoff).
  run_after timestamptz NOT NULL DEFAULT now(),
  locked_at timestamptz,
  locked_by text
    CONSTRAINT jobs_locked_by_length CHECK (locked_by IS NULL OR char_length(locked_by) BETWEEN 1 AND 200),
  last_error text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb
    CONSTRAINT jobs_payload_object CHECK (jsonb_typeof(payload) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  CONSTRAINT jobs_lock_rule
    CHECK ((status = 'running') = (locked_at IS NOT NULL AND locked_by IS NOT NULL)),
  CONSTRAINT jobs_finished_rule
    CHECK ((status IN ('succeeded', 'failed')) = (finished_at IS NOT NULL))
);

CREATE INDEX jobs_queue_idx ON jobs (run_after, created_at) WHERE status = 'queued';
CREATE INDEX jobs_running_locked_at_idx ON jobs (locked_at) WHERE status = 'running';
CREATE INDEX jobs_package_idx ON jobs (package_id, created_at);
CREATE UNIQUE INDEX jobs_one_active_per_package_type
  ON jobs (package_id, type) WHERE status IN ('queued', 'running');

CREATE TRIGGER jobs_set_updated_at
  BEFORE UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION station_set_updated_at();

COMMENT ON TABLE jobs IS
  'Station work queue (checks, publish), claimed with FOR UPDATE SKIP LOCKED.';

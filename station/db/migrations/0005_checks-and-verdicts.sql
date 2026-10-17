-- Up Migration
-- Acceptance check runs, per-rule results and the verdict of each package.
--
-- A checks job owns at most one run (check_runs_job_id_key); re-running the job replaces that
-- run (delete it: its results cascade) and upserts the package's single verdict row.
-- verdicts.document is the verdict exactly as served by GET /packages/{packageId}/verdict
-- (contract/schema/verdict.schema.json); the other verdict columns are copies for querying.

CREATE TABLE check_runs (
  run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES packages (package_id),
  job_id uuid REFERENCES jobs (job_id),
  status text NOT NULL DEFAULT 'running'
    CONSTRAINT check_runs_status_valid CHECK (status IN ('running', 'completed', 'failed')),
  evaluator_name text
    CONSTRAINT check_runs_evaluator_name_length
    CHECK (evaluator_name IS NULL OR char_length(evaluator_name) BETWEEN 1 AND 100),
  evaluator_version text
    CONSTRAINT check_runs_evaluator_version_length
    CHECK (evaluator_version IS NULL OR char_length(evaluator_version) BETWEEN 1 AND 50),
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  error text,
  CONSTRAINT check_runs_finished_rule CHECK ((status = 'running') = (finished_at IS NULL)),
  CONSTRAINT check_runs_failed_has_error CHECK (status <> 'failed' OR error IS NOT NULL)
);

CREATE UNIQUE INDEX check_runs_job_id_key ON check_runs (job_id) WHERE job_id IS NOT NULL;
CREATE INDEX check_runs_package_idx ON check_runs (package_id, started_at DESC);

COMMENT ON TABLE check_runs IS 'One execution of the acceptance checks on a package.';

CREATE TABLE check_results (
  run_id uuid NOT NULL REFERENCES check_runs (run_id) ON DELETE CASCADE,
  -- Position of the rule in the verdict's checks list.
  ordinal integer NOT NULL CONSTRAINT check_results_ordinal_nonnegative CHECK (ordinal >= 0),
  rule_id text NOT NULL
    CONSTRAINT check_results_rule_id_valid
    CHECK (char_length(rule_id) <= 100 AND rule_id ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$'),
  title text NOT NULL
    CONSTRAINT check_results_title_length CHECK (char_length(title) BETWEEN 1 AND 200),
  status text NOT NULL
    CONSTRAINT check_results_status_valid CHECK (status IN ('passed', 'failed', 'not_applicable')),
  -- Findings of this rule (verdict finding objects). The verdict document stays the source of
  -- truth for the full findings list.
  findings jsonb NOT NULL DEFAULT '[]'::jsonb
    CONSTRAINT check_results_findings_array CHECK (jsonb_typeof(findings) = 'array'),
  PRIMARY KEY (run_id, rule_id),
  CONSTRAINT check_results_run_ordinal_key UNIQUE (run_id, ordinal)
);

COMMENT ON TABLE check_results IS 'Result of each rule in a check run (the verdict checks list).';

CREATE TABLE verdicts (
  verdict_id uuid PRIMARY KEY,
  package_id uuid NOT NULL REFERENCES packages (package_id),
  run_id uuid REFERENCES check_runs (run_id) ON DELETE SET NULL,
  outcome text NOT NULL CONSTRAINT verdicts_outcome_valid CHECK (outcome IN ('ready', 'limited', 'blocked')),
  evaluated_at timestamptz NOT NULL,
  document jsonb NOT NULL
    CONSTRAINT verdicts_document_object CHECK (jsonb_typeof(document) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verdicts_package_id_key UNIQUE (package_id),
  CONSTRAINT verdicts_document_matches CHECK (COALESCE(
    document ->> 'verdictId' = verdict_id::text
    AND document ->> 'packageId' = package_id::text
    AND document ->> 'outcome' = outcome, false)
  )
);

CREATE TRIGGER verdicts_set_updated_at
  BEFORE UPDATE ON verdicts
  FOR EACH ROW EXECUTE FUNCTION station_set_updated_at();

COMMENT ON TABLE verdicts IS 'The current verdict of each package (contract verdict document).';

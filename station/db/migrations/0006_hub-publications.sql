-- Up Migration
-- Publication of each package revision to the HUB project Files tab.
--
-- One row per package (packages are per revision), so a retry updates the same row and never
-- publishes twice. files records every file already uploaded or linked (name, folder, HUB
-- document id, ...) so a retry skips them. error holds the last HUB error (status, message).

CREATE TABLE hub_publications (
  publication_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES packages (package_id),
  -- Verdict that was published (no foreign key: re-running the checks replaces the verdict).
  verdict_id uuid,
  status text NOT NULL DEFAULT 'pending'
    CONSTRAINT hub_publications_status_valid
    CHECK (status IN ('pending', 'publishing', 'published', 'publish_failed')),
  attempts integer NOT NULL DEFAULT 0
    CONSTRAINT hub_publications_attempts_nonnegative CHECK (attempts >= 0),
  files jsonb NOT NULL DEFAULT '[]'::jsonb
    CONSTRAINT hub_publications_files_array CHECK (jsonb_typeof(files) = 'array'),
  error jsonb
    CONSTRAINT hub_publications_error_object CHECK (error IS NULL OR jsonb_typeof(error) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  CONSTRAINT hub_publications_package_id_key UNIQUE (package_id),
  CONSTRAINT hub_publications_published_rule
    CHECK ((status = 'published') = (published_at IS NOT NULL)),
  CONSTRAINT hub_publications_failed_has_error
    CHECK (status <> 'publish_failed' OR error IS NOT NULL)
);

CREATE INDEX hub_publications_status_idx ON hub_publications (status)
  WHERE status <> 'published';

CREATE TRIGGER hub_publications_set_updated_at
  BEFORE UPDATE ON hub_publications
  FOR EACH ROW EXECUTE FUNCTION station_set_updated_at();

COMMENT ON TABLE hub_publications IS
  'HUB publication state of each package revision; retries reuse the row.';

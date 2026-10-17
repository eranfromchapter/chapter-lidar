-- Up Migration
-- HUB projects (deals with a confirmed property address), cached by the station API.
-- Rows expire after the cache TTL (10 minutes, set by the API through expires_at).

CREATE TABLE projects_cache (
  deal_id station_deal_id PRIMARY KEY,
  project_name text
    CONSTRAINT projects_cache_project_name_length
    CHECK (project_name IS NULL OR char_length(project_name) BETWEEN 1 AND 200),
  -- Single-line address exactly as shown by the HUB.
  address_formatted text NOT NULL
    CONSTRAINT projects_cache_address_length
    CHECK (char_length(address_formatted) BETWEEN 1 AND 300),
  -- Last update time reported by the HUB, for "most recently updated first".
  hub_updated_at timestamptz,
  -- Minimal extra HUB fields the API needs; never credentials.
  payload jsonb NOT NULL DEFAULT '{}'::jsonb
    CONSTRAINT projects_cache_payload_object CHECK (jsonb_typeof(payload) = 'object'),
  fetched_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  CONSTRAINT projects_cache_expiry_after_fetch CHECK (expires_at > fetched_at)
);

CREATE INDEX projects_cache_expires_at_idx ON projects_cache (expires_at);
CREATE INDEX projects_cache_hub_updated_at_idx ON projects_cache (hub_updated_at DESC NULLS LAST);

COMMENT ON TABLE projects_cache IS
  'HUB projects with a confirmed address, cached by the station API until expires_at.';

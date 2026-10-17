-- Up Migration
-- Who did what, to which target, and when, for every write. Append-only.
-- details never holds secrets (the API redacts tokens, SAS URLs and keys before writing).

CREATE TABLE audit_log (
  audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  actor_type text NOT NULL
    CONSTRAINT audit_log_actor_type_valid CHECK (actor_type IN ('user', 'service', 'system')),
  -- Entra object id of the user or service principal.
  actor_id station_actor_id,
  actor_name station_actor_name,
  actor_roles text[] NOT NULL DEFAULT '{}',
  -- Dotted action, for example package.create.
  action text NOT NULL
    CONSTRAINT audit_log_action_valid
    CHECK (char_length(action) <= 100 AND action ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  target_type text NOT NULL
    CONSTRAINT audit_log_target_type_valid
    CHECK (char_length(target_type) <= 64 AND target_type ~ '^[a-z][a-z0-9_]*$'),
  target_id text
    CONSTRAINT audit_log_target_id_length
    CHECK (target_id IS NULL OR char_length(target_id) BETWEEN 1 AND 1024),
  details jsonb NOT NULL DEFAULT '{}'::jsonb
    CONSTRAINT audit_log_details_object CHECK (jsonb_typeof(details) = 'object'),
  request_id text
    CONSTRAINT audit_log_request_id_length
    CHECK (request_id IS NULL OR char_length(request_id) BETWEEN 1 AND 128),
  CONSTRAINT audit_log_actor_rule CHECK (actor_type = 'system' OR actor_id IS NOT NULL)
);

CREATE INDEX audit_log_occurred_at_idx ON audit_log (occurred_at);
CREATE INDEX audit_log_target_idx ON audit_log (target_type, target_id, occurred_at);
CREATE INDEX audit_log_actor_idx ON audit_log (actor_id, occurred_at) WHERE actor_id IS NOT NULL;

CREATE TRIGGER audit_log_append_only
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION station_reject_change();

CREATE TRIGGER audit_log_no_truncate
  BEFORE TRUNCATE ON audit_log
  FOR EACH STATEMENT EXECUTE FUNCTION station_reject_change();

COMMENT ON TABLE audit_log IS 'Append-only record of every write: who, what, which target, when.';

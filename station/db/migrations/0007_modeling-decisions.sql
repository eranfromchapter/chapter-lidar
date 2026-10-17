-- Up Migration
-- Log of the package sources a BIM operator relied on for each modeling decision.
-- Append-only: decisions are never edited or deleted.

CREATE TABLE modeling_decisions (
  decision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES packages (package_id),
  element text NOT NULL
    CONSTRAINT modeling_decisions_element_length CHECK (char_length(element) BETWEEN 1 AND 300),
  decision text NOT NULL
    CONSTRAINT modeling_decisions_decision_length CHECK (char_length(decision) BETWEEN 1 AND 2000),
  capture_id uuid,
  area_key station_area_key,
  -- DecisionSource objects: {path, controlId?, elementId?}.
  sources jsonb NOT NULL
    CONSTRAINT modeling_decisions_sources_nonempty
    CHECK (jsonb_typeof(sources) = 'array' AND jsonb_array_length(sources) >= 1),
  note text
    CONSTRAINT modeling_decisions_note_length
    CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 2000),
  decided_by_id station_actor_id NOT NULL,
  decided_by_name station_actor_name NOT NULL,
  decided_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT modeling_decisions_capture_pair CHECK ((capture_id IS NULL) = (area_key IS NULL))
);

CREATE INDEX modeling_decisions_package_idx
  ON modeling_decisions (package_id, decided_at, decision_id);

CREATE TRIGGER modeling_decisions_append_only
  BEFORE UPDATE OR DELETE ON modeling_decisions
  FOR EACH ROW EXECUTE FUNCTION station_reject_change();

CREATE TRIGGER modeling_decisions_no_truncate
  BEFORE TRUNCATE ON modeling_decisions
  FOR EACH STATEMENT EXECUTE FUNCTION station_reject_change();

COMMENT ON TABLE modeling_decisions IS
  'Append-only log of the package source used for each modeling decision.';

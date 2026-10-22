// "Verdicts always show a word and a shape: ● Ready · ▲ Limited · ■ Blocked." with the shapes
// drawn as SVG (the self-hosted Inter subset has no geometric shapes).

import { StatusGlyph } from "./hub/StatusGlyph";

export function VerdictLegend() {
  return (
    <p className="legend" style={{ margin: 0 }}>
      Verdicts always show a word and a shape:{" "}
      <span className="legend__item">
        <StatusGlyph kind="circle" />
        Ready
      </span>{" "}
      ·{" "}
      <span className="legend__item">
        <StatusGlyph kind="triangle" />
        Limited
      </span>{" "}
      ·{" "}
      <span className="legend__item">
        <StatusGlyph kind="square" />
        Blocked.
      </span>
    </p>
  );
}

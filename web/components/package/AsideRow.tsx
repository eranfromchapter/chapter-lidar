// A label/value row of the package page's aside cards (web-review §6.4.9).

import type { ReactNode } from "react";

export interface AsideRowProps {
  readonly label: string;
  readonly children: ReactNode;
  /** The value may wrap: the label keeps its width. */
  readonly wraps?: boolean;
  readonly mono?: boolean;
  readonly muted?: boolean;
  readonly glyph?: boolean;
}

export function AsideRow({
  label,
  children,
  wraps = false,
  mono = false,
  muted = false,
  glyph = false,
}: AsideRowProps) {
  const classes = ["kv__value", mono ? "mono" : "", glyph ? "kv__value--glyph" : ""]
    .filter((part) => part.length > 0)
    .join(" ");
  return (
    <div className="kv">
      <span className={`kv__label${wraps ? " kv__label--fixed" : ""}`}>{label}</span>
      <span className={classes} style={muted ? { color: "var(--text-muted)" } : undefined}>
        {children}
      </span>
    </div>
  );
}

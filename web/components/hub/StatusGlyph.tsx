// Status shapes (web-review §2.4): drawn as SVG, never as font characters, so the self-hosted
// Inter subset is never asked for ● ▲ ■. Hidden from assistive technology: a word always
// accompanies the shape.

export type GlyphKind = "circle" | "triangle" | "square" | "dash" | "ring";

export interface StatusGlyphProps {
  readonly kind: GlyphKind;
  /** Width and height in px (default 9). */
  readonly size?: number;
  /** Fill (or ring stroke); defaults to currentColor. */
  readonly color?: string;
}

export function StatusGlyph({ kind, size = 9, color = "currentColor" }: StatusGlyphProps) {
  const common = {
    width: size,
    height: size,
    viewBox: "0 0 10 10",
    "aria-hidden": true as const,
    focusable: false as const,
  };
  switch (kind) {
    case "circle":
      return (
        <svg {...common} fill={color}>
          <circle cx="5" cy="5" r="4.6" />
        </svg>
      );
    case "triangle":
      return (
        <svg {...common} fill={color}>
          <path d="M5 .6 9.6 9.4H.4z" />
        </svg>
      );
    case "square":
      return (
        <svg {...common} fill={color}>
          <rect x=".6" y=".6" width="8.8" height="8.8" />
        </svg>
      );
    case "dash":
      return (
        <svg {...common} fill={color}>
          <rect x="1" y="4.3" width="8" height="1.4" />
        </svg>
      );
    case "ring":
      return (
        <svg {...common} fill="none">
          <circle cx="5" cy="5" r="4" fill="none" stroke={color} strokeWidth="1.4" />
        </svg>
      );
  }
}

/** The shape of a verdict outcome. */
export const OUTCOME_GLYPH = {
  ready: "circle",
  limited: "triangle",
  blocked: "square",
} as const satisfies Record<"ready" | "limited" | "blocked", GlyphKind>;

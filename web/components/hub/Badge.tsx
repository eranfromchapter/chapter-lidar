// HUB Badge (web-review §2.4): a pill label in one of six tones, soft (default) or solid.

import type { ReactNode } from "react";

export type BadgeTone = "neutral" | "accent" | "success" | "warning" | "danger" | "info";

export interface BadgeProps {
  readonly tone?: BadgeTone;
  readonly variant?: "soft" | "solid";
  readonly children: ReactNode;
}

export function Badge({ tone = "neutral", variant = "soft", children }: BadgeProps) {
  return <span className={`hub-badge hub-badge--${variant} hub-badge--${tone}`}>{children}</span>;
}

// HUB Card (web-review §2.4): white, 16 px corners, a hairline and a small shadow. A card with a
// table clips the header row to its corners and scrolls the table when narrow.

import type { ReactNode } from "react";

export interface CardProps {
  readonly padding?: "none" | "sm" | "md" | "lg";
  /** Holds a table: overflow hidden at the corners. */
  readonly table?: boolean;
  /** Id of the card's title (the section's accessible name). */
  readonly labelledBy?: string;
  /** Accessible name when the card has no visible title. */
  readonly label?: string;
  readonly id?: string;
  readonly role?: "alert" | "status";
  readonly className?: string;
  readonly dataOutcome?: string;
  readonly children: ReactNode;
}

export function Card({
  padding = "md",
  table = false,
  labelledBy,
  label,
  id,
  role,
  className,
  dataOutcome,
  children,
}: CardProps) {
  const classes = [
    "hub-card",
    padding === "none" ? "" : `hub-card--${padding}`,
    table ? "hub-card--table" : "",
    className ?? "",
  ]
    .filter((part) => part.length > 0)
    .join(" ");
  const named = labelledBy !== undefined || label !== undefined;
  const Tag = named ? "section" : "div";
  return (
    <Tag
      id={id}
      className={classes}
      role={role}
      aria-labelledby={labelledBy}
      aria-label={label}
      data-outcome={dataOutcome}
    >
      {children}
    </Tag>
  );
}

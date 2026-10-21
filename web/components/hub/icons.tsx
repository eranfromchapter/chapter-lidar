// Stroke icons of the HUB drawing (web-review §2.4): inline SVG, 24-unit view box, round caps and
// joins, hidden from assistive technology (the text next to them names the action).

import type { ReactNode } from "react";

export interface IconProps {
  readonly size?: number;
  /** Stroke colour; defaults to currentColor. */
  readonly stroke?: string;
  readonly strokeWidth?: number;
}

function Icon({
  size = 18,
  stroke = "currentColor",
  strokeWidth = 2,
  children,
}: IconProps & { readonly children: ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke={stroke}
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

export function ProjectsIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
    </Icon>
  );
}

export function PackagesIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M21 8l-9-5-9 5v8l9 5 9-5z" />
      <path d="M3 8l9 5 9-5M12 13v9" />
    </Icon>
  );
}

export function DecisionLogIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M10 6h11M10 12h11M10 18h11M3 6l1.5 1.5L7 5M3 12l1.5 1.5L7 11M3 18l1.5 1.5L7 17" />
    </Icon>
  );
}

export function IntakeGuideIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M2 4h6a4 4 0 0 1 4 4v12a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v12a3 3 0 0 1 3-3h7z" />
    </Icon>
  );
}

export function SearchIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <circle cx="11" cy="11" r="7" />
      <path d="M20 20l-3.5-3.5" />
    </Icon>
  );
}

export function BackIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path d="M19 12H5M12 19l-7-7 7-7" />
    </Icon>
  );
}

export function DownloadIcon(props: IconProps) {
  return (
    <Icon strokeWidth={2.2} {...props}>
      <path d="M12 3v12M6 11l6 6 6-6M4 21h16" />
    </Icon>
  );
}

/** The select caret, drawn because the self-hosted Inter subset has no "▾". */
export function CaretIcon() {
  return (
    <svg
      width="10"
      height="6"
      viewBox="0 0 10 6"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M1 1l4 4 4-4" />
    </svg>
  );
}

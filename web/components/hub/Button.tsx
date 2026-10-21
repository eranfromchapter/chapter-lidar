// HUB Button (web-review §2.4): a pill. Renders a link when it has an href, else a button.
// Hover, press and focus are CSS (hub.css .hub-btn).

import type { ReactNode } from "react";

export type ButtonVariant = "primary" | "accent" | "outline" | "ghost" | "danger";
export type ButtonSize = "sm" | "md" | "lg";

export interface ButtonProps {
  readonly variant?: ButtonVariant;
  readonly size?: ButtonSize;
  readonly iconLeft?: ReactNode;
  readonly fullWidth?: boolean;
  readonly href?: string;
  /** Opens in a new tab with rel="noopener noreferrer" and a hidden "(opens in a new tab)". */
  readonly external?: boolean;
  readonly rel?: string;
  readonly type?: "button" | "submit";
  readonly disabled?: boolean;
  readonly onClick?: () => void;
  readonly "aria-label"?: string;
  readonly "aria-expanded"?: boolean;
  readonly "aria-controls"?: string;
  readonly className?: string;
  readonly children: ReactNode;
}

export function buttonClass(
  variant: ButtonVariant = "primary",
  size: ButtonSize = "md",
  fullWidth = false,
  extra?: string,
): string {
  return [
    "hub-btn",
    `hub-btn--${variant}`,
    `hub-btn--${size}`,
    fullWidth ? "hub-btn--full" : "",
    extra ?? "",
  ]
    .filter((part) => part.length > 0)
    .join(" ");
}

export function Button({
  variant = "primary",
  size = "md",
  iconLeft,
  fullWidth = false,
  href,
  external = false,
  rel,
  type = "button",
  disabled = false,
  onClick,
  className,
  children,
  ...aria
}: ButtonProps) {
  const classes = buttonClass(variant, size, fullWidth, className);
  if (href !== undefined) {
    return (
      <a
        href={href}
        className={classes}
        {...(external ? { target: "_blank", rel: "noopener noreferrer" } : {})}
        {...(rel === undefined || external ? {} : { rel })}
        aria-label={aria["aria-label"]}
      >
        {iconLeft}
        {children}
        {external ? <span className="visually-hidden"> (opens in a new tab)</span> : null}
      </a>
    );
  }
  return (
    <button
      type={type}
      className={classes}
      disabled={disabled}
      onClick={onClick}
      aria-label={aria["aria-label"]}
      aria-expanded={aria["aria-expanded"]}
      aria-controls={aria["aria-controls"]}
    >
      {iconLeft}
      {children}
    </button>
  );
}

// HUB TextField (web-review §2.4): a native input in a 10 px rounded frame, with an optional
// visible label (else an aria-label), hint and error. Works controlled (value + onChange) or
// uncontrolled (defaultValue).

import type { ChangeEvent } from "react";

export interface TextFieldProps {
  readonly id: string;
  readonly name?: string;
  readonly label?: string;
  /** Accessible name when there is no visible label. */
  readonly ariaLabel?: string;
  readonly placeholder?: string;
  readonly type?: "text" | "search";
  readonly defaultValue?: string;
  readonly value?: string;
  readonly onChange?: (event: ChangeEvent<HTMLInputElement>) => void;
  readonly required?: boolean;
  readonly maxLength?: number;
  readonly hint?: string;
  readonly error?: string;
  /** false: the field keeps a fixed width (filter bars). */
  readonly fullWidth?: boolean;
  /** Width in px when not full width. */
  readonly width?: number;
}

export function TextField({
  id,
  name,
  label,
  ariaLabel,
  placeholder,
  type = "text",
  defaultValue,
  value,
  onChange,
  required,
  maxLength,
  hint,
  error,
  fullWidth = true,
  width,
}: TextFieldProps) {
  return (
    <div
      className={`hub-field${fullWidth ? "" : " hub-field--inline"}`}
      style={fullWidth || width === undefined ? undefined : { width }}
    >
      {label === undefined ? null : (
        <label className="hub-field__label" htmlFor={id}>
          {label}
        </label>
      )}
      <div
        className="hub-input-wrap"
        style={error === undefined ? undefined : { borderColor: "var(--status-danger)" }}
      >
        <input
          id={id}
          name={name}
          type={type}
          className="hub-input"
          placeholder={placeholder}
          aria-label={label === undefined ? ariaLabel : undefined}
          aria-invalid={error === undefined ? undefined : true}
          required={required}
          maxLength={maxLength}
          autoComplete="off"
          {...(value === undefined ? { defaultValue } : { value, onChange })}
        />
      </div>
      {hint === undefined ? null : <span className="hub-field__hint">{hint}</span>}
      {error === undefined ? null : (
        <span className="hub-field__hint" style={{ color: "var(--status-danger)" }}>
          {error}
        </span>
      )}
    </div>
  );
}

// HUB Select (web-review §2.4): a native select without the platform arrow, with the HUB caret
// drawn in SVG. Options may be grouped. Works controlled (value + onChange) or uncontrolled
// (defaultValue).

import type { ChangeEvent } from "react";
import { CaretIcon } from "./icons";

export interface SelectOption {
  readonly value: string;
  readonly label: string;
  readonly disabled?: boolean;
}

export interface SelectGroup {
  readonly label: string;
  readonly options: readonly SelectOption[];
}

export interface SelectProps {
  readonly id: string;
  readonly name?: string;
  readonly label?: string;
  /** Accessible name when there is no visible label. */
  readonly ariaLabel?: string;
  readonly options?: readonly SelectOption[];
  readonly groups?: readonly SelectGroup[];
  readonly defaultValue?: string;
  readonly value?: string;
  readonly onChange?: (event: ChangeEvent<HTMLSelectElement>) => void;
  readonly required?: boolean;
  readonly fullWidth?: boolean;
  /** Width in px when not full width. */
  readonly width?: number;
}

function optionsOf(options: readonly SelectOption[]) {
  return options.map((option) => (
    <option key={option.value} value={option.value} disabled={option.disabled}>
      {option.label}
    </option>
  ));
}

export function Select({
  id,
  name,
  label,
  ariaLabel,
  options = [],
  groups = [],
  defaultValue,
  value,
  onChange,
  required,
  fullWidth = true,
  width,
}: SelectProps) {
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
      <div className="hub-select-wrap">
        <select
          id={id}
          name={name}
          className="hub-select"
          aria-label={label === undefined ? ariaLabel : undefined}
          required={required}
          {...(value === undefined ? { defaultValue } : { value, onChange })}
        >
          {optionsOf(options)}
          {groups.map((group) => (
            <optgroup key={group.label} label={group.label}>
              {optionsOf(group.options)}
            </optgroup>
          ))}
        </select>
        <span className="hub-select__caret">
          <CaretIcon />
        </span>
      </div>
    </div>
  );
}

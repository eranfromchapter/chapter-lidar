// HUB progress bar (web-review §2.4): mint fill on a grey track; "table" is 140 x 4 px under a
// table cell's text, "block" is full width, 6 px.

export interface ProgressBarProps {
  /** 0 to 100. */
  readonly value: number;
  readonly label: string;
  readonly size?: "table" | "block";
}

export function ProgressBar({ value, label, size = "block" }: ProgressBarProps) {
  const percent = Math.min(100, Math.max(0, Math.round(value)));
  return (
    <div
      className={`hub-progress hub-progress--${size}`}
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={percent}
      aria-label={label}
    >
      <div className="hub-progress__fill" style={{ width: `${percent}%` }} />
    </div>
  );
}

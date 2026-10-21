// HUB Avatar (web-review §2.4): initials in a mint circle. Hidden from assistive technology: the
// name is printed next to it.

/** First letter of each of the first two words, upper case; "?" for an empty name. */
export function initials(name: string): string {
  const letters = name
    .trim()
    .split(/\s+/)
    .filter((word) => word.length > 0)
    .slice(0, 2)
    .map((word) => [...word][0]?.toUpperCase() ?? "")
    .join("");
  return letters.length === 0 ? "?" : letters;
}

export function Avatar({ name, size = 34 }: { readonly name: string; readonly size?: number }) {
  return (
    <span
      className="hub-avatar"
      aria-hidden="true"
      style={{ width: size, height: size, fontSize: Math.round(size * 0.4) }}
    >
      {initials(name)}
    </span>
  );
}

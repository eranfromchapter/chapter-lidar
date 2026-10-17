// Address normalization for the property match (check 3).
//
// Both addresses go through the same steps, so normalization can only make equal addresses
// compare equal; it never invents a match between different street numbers or names:
//   Unicode NFKC, lower case, "&" to "and", punctuation to spaces, collapsed whitespace, and
//   common USPS street-suffix, direction and unit words mapped to one abbreviation.

const WORDS: Readonly<Record<string, string>> = {
  street: "st",
  avenue: "ave",
  av: "ave",
  road: "rd",
  boulevard: "blvd",
  drive: "dr",
  lane: "ln",
  place: "pl",
  court: "ct",
  terrace: "ter",
  parkway: "pkwy",
  highway: "hwy",
  square: "sq",
  circle: "cir",
  north: "n",
  south: "s",
  east: "e",
  west: "w",
  northeast: "ne",
  northwest: "nw",
  southeast: "se",
  southwest: "sw",
  apartment: "apt",
  suite: "ste",
  floor: "fl",
  number: "no",
};

export function normalizeAddress(address: string): string {
  return address
    .normalize("NFKC")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .split(/\s+/)
    .filter((word) => word.length > 0)
    .map((word) => WORDS[word] ?? word)
    .join(" ");
}

/** True when two addresses are equal after normalization (and the first is not empty). */
export function addressesMatch(recorded: string, hub: string): boolean {
  const a = normalizeAddress(recorded);
  return a.length > 0 && a === normalizeAddress(hub);
}

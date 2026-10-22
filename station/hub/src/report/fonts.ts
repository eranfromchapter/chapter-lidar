// Registers the embedded fonts: Inter Regular as "Inter" and Inter SemiBold as "Inter-SB"
// (pdfkit subsets them on embedding). Times-Roman and Courier are PDF standard fonts.

import { INTER_REGULAR_TTF_BASE64, INTER_SEMIBOLD_TTF_BASE64 } from "./brand-assets.generated.js";
import { FONT } from "./tokens.js";

let regular: Buffer | undefined;
let semibold: Buffer | undefined;

export function registerFonts(doc: PDFKit.PDFDocument): void {
  regular ??= Buffer.from(INTER_REGULAR_TTF_BASE64.join(""), "base64");
  semibold ??= Buffer.from(INTER_SEMIBOLD_TTF_BASE64.join(""), "base64");
  doc.registerFont(FONT.sans, regular);
  doc.registerFont(FONT.semibold, semibold);
}

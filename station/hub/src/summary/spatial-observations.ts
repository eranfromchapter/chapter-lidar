// The "Spatial Observations" section of a PM or design brief, written from a room summary: the
// rooms with their sizes and fixtures, the quantities an estimate is priced from, and what to
// check before pricing. Plain text, so a brief generator can paste it in or hand it to a model.

import type { RoomSummary, RoomSummaryRoom, SummaryTotals } from "./room-summary.js";

export function spatialObservations(summary: RoomSummary): string {
  const lines: string[] = [];
  const measured = summary.floors.filter((floor) => floor.status === "ok");
  lines.push("Spatial Observations (from Chapter Capture)");
  lines.push(
    `${plural(summary.totals.rooms, "room")}, ${area(summary.totals.floorAreaSqFt)} ` +
      `over ${plural(measured.length, "floor")}.`,
  );
  const unmeasured = summary.floors.length - measured.length;
  if (unmeasured > 0) {
    lines.push(`${plural(unmeasured, "floor")} could not be measured (no readable scan).`);
  }

  for (const floor of measured) {
    lines.push("");
    const title = floor.name ?? floor.areaKey;
    lines.push(
      `${title}: ${plural(floor.totals.rooms, "room")}, ${area(floor.totals.floorAreaSqFt)}`,
    );
    for (const room of floor.rooms) {
      lines.push(`- ${roomLine(room)}`);
    }
  }

  lines.push("");
  lines.push("Quantities for the estimate");
  lines.push(...quantityLines(summary.totals).map((line) => `- ${line}`));

  const checks = measured.flatMap((floor) =>
    floor.rooms
      .filter((room) => room.uncertain.length > 0)
      .map((room) => `- ${room.name}: ${room.uncertain.join("; ")}`),
  );
  if (checks.length > 0) {
    lines.push("");
    lines.push("Check before pricing");
    lines.push(...checks);
  }
  return `${lines.join("\n")}\n`;
}

function roomLine(room: RoomSummaryRoom): string {
  const type = typeName(room.type);
  const named = room.name.toLowerCase().includes(type) ? room.name : `${room.name} (${type})`;
  const parts = [area(room.floorAreaSqFt), `ceiling ${number(room.ceilingHeightFt)} ft`];
  if (room.doors > 0) {
    parts.push(plural(room.doors, "door"));
  }
  if (room.windows > 0) {
    parts.push(plural(room.windows, "window"));
  }
  const fixtures = counts(room.fixtures);
  return `${named}: ${parts.join(", ")}${fixtures === "" ? "" : `; ${fixtures}`}.`;
}

function quantityLines(totals: SummaryTotals): string[] {
  const byType = Object.entries(totals.byRoomType)
    .map(([type, entry]) => `${typeName(type)} ${number(entry.floorAreaSqFt)}`)
    .join(", ");
  const lines = [
    `Floor area: ${area(totals.floorAreaSqFt)}${byType === "" ? "" : ` (${byType})`}`,
    `Paintable walls: ${area(totals.paintableWallAreaSqFt)}; ceilings: ${area(totals.ceilingAreaSqFt)}`,
    `Baseboard: ${number(totals.baseboardFt)} ft`,
    `Doors: ${totals.doors}; windows: ${totals.windows}`,
  ];
  const fixtures = counts(totals.fixtures);
  if (fixtures !== "") {
    lines.push(`Fixtures: ${fixtures}`);
  }
  return lines;
}

/** RoomPlan's object words as a brief reads them. */
const CATEGORY_NAMES: Readonly<Record<string, string>> = { storage: "cabinets/storage" };

function counts(record: Readonly<Record<string, number>>): string {
  return Object.entries(record)
    .map(([category, count]) => {
      const name = CATEGORY_NAMES[category] ?? category;
      return count === 1 ? name : `${name} x${count}`;
    })
    .join(", ");
}

function typeName(type: string): string {
  return type.replace(/_/g, " ");
}

function area(squareFeet: number): string {
  return `${number(squareFeet)} sq ft`;
}

function number(value: number): string {
  return value.toLocaleString("en-US", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
}

function plural(count: number, noun: string): string {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

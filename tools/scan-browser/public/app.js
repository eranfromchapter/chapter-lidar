// Scan browser UI. No build step, no dependencies (the 3D viewer is loaded only when a GLB is
// previewed). Every string that comes from the data folder reaches the page through textContent
// or setAttribute, never innerHTML, so file names, labels and JSON values are always plain text.

// The page's CSP (server.mjs) allows exactly this URL; the hash pins its content, so a changed
// file from the CDN is refused instead of run.
const MODEL_VIEWER_URL =
  "https://cdn.jsdelivr.net/npm/@google/model-viewer@3.5.0/dist/model-viewer.min.js";
const MODEL_VIEWER_SRI = "sha384-Ftcjj/GNLxPvzNDftO/oryXB9aGxsGZY9JGqsXG0uUKgQDl9RfDgsx9NJ/4IVNPe";
const JSON_PAGE = 200;

const app = document.getElementById("app");
const lightbox = document.getElementById("lightbox");
let syncTimer = 0;
let renderToken = 0;

// ---------------------------------------------------------------------------------------------
// DOM helpers

function setAttrs(el, attrs) {
  for (const [key, value] of Object.entries(attrs ?? {})) {
    if (value === null || value === undefined || value === false) continue;
    if (key.startsWith("on") && typeof value === "function") {
      el.addEventListener(key.slice(2), value);
    } else {
      el.setAttribute(key, value === true ? "" : String(value));
    }
  }
}

function appendAll(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
}

function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  setAttrs(el, attrs);
  appendAll(el, children);
  return el;
}

function s(tag, attrs, ...children) {
  const el = document.createElementNS("http://www.w3.org/2000/svg", tag);
  setAttrs(el, attrs);
  appendAll(el, children);
  return el;
}

const muted = (text) => h("p", { class: "muted" }, text);
const mono = (text) => h("span", { class: "mono" }, text);
const errorBox = (text) => h("p", { class: "problem" }, text);
const count = (list) => (list?.length ? h("span", { class: "count" }, String(list.length)) : null);

// ---------------------------------------------------------------------------------------------
// Formatting and URLs

function fmtBytes(n) {
  if (!Number.isFinite(n)) return "—";
  const units = ["B", "KB", "MB", "GB"];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return i === 0 ? `${v} B` : `${v.toFixed(v < 10 ? 2 : 1)} ${units[i]}`;
}

function fmtDate(value) {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return String(value);
  return d.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function fmtNum(n, digits = 2) {
  if (!Number.isFinite(n)) return "—";
  return n.toLocaleString(undefined, {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

const enc = encodeURIComponent;
const fileUrl = (p) => `/api/file?path=${enc(p)}`;
const downloadUrl = (p) => `/api/file?path=${enc(p)}&download=1`;
const photoUrl = (f, w) => `/api/photo?path=${enc(f.path)}&w=${w}&v=${f.mtimeMs}`;
const visitHref = (id) => `#/visit/${enc(id)}`;

async function api(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: { "X-Scan-Browser": "1", ...(options.headers ?? {}) },
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(body?.error ?? `${response.status} ${response.statusText}`);
  return body;
}

function factList(pairs) {
  const shown = pairs.filter(([, v]) => v !== null && v !== undefined && v !== "");
  if (shown.length === 0) return null;
  return h(
    "dl",
    { class: "facts" },
    shown.map(([k, v]) => [h("dt", {}, k), h("dd", {}, String(v))]),
  );
}

// Status chips in the Chapter verdict tones. A verdict always carries its word and a shape too
// (● ready, ▲ limited, ■ blocked), never colour alone; the steps before it (scanned, built,
// sealed) are plain chips.
const CHIP_TONES = {
  uploaded: ["ready", "●"],
  upload: ["limited", "▲"],
  "upload-error": ["blocked", "■"],
  empty: ["muted", null],
};

function chip(key, label) {
  const [tone, shape] = Object.hasOwn(CHIP_TONES, key) ? CHIP_TONES[key] : ["step", null];
  return h(
    "span",
    { class: `chip chip-${tone}` },
    shape ? h("span", { class: "shape", "aria-hidden": "true" }, shape) : null,
    label,
  );
}

function statusChips(list) {
  return h(
    "div",
    { class: "chips" },
    (list ?? []).map((st) => chip(st.key, st.label)),
  );
}

function card(title, ...children) {
  return h("section", { class: "card" }, h("h2", {}, title), ...children);
}

// ---------------------------------------------------------------------------------------------
// Routing

function route() {
  clearTimeout(syncTimer);
  if (lightbox.open) lightbox.close();
  const token = ++renderToken;
  const match = /^#\/visit\/(.+)$/.exec(location.hash);
  let view;
  try {
    view = match ? renderVisit(decodeURIComponent(match[1]), token) : renderList(token);
  } catch (err) {
    view = Promise.reject(err);
  }
  view.catch((err) => {
    if (token === renderToken)
      app.replaceChildren(h("a", { href: "#/" }, "← All visits"), errorBox(err.message));
  });
  window.scrollTo(0, 0);
}

function setDataDir(dir) {
  const el = document.getElementById("data-dir");
  el.textContent = dir ? `Data: ${dir}` : "";
  el.title = dir ?? "";
}

// ---------------------------------------------------------------------------------------------
// Visits list and sync

async function renderList(token) {
  document.title = "Scan browser";
  app.replaceChildren(muted("Loading visits…"));
  const [data, sync] = await Promise.all([api("/api/visits"), api("/api/sync")]);
  if (token !== renderToken) return;
  setDataDir(data.dataDir);

  const syncBox = h("section", { class: "card sync" });
  renderSync(syncBox, sync);
  if (sync.status === "running") pollSync(syncBox);

  const heads = ["Date", "Visit", "Operator", "Areas", "Files", "Status"];
  const list = data.visits.length
    ? h(
        "div",
        { class: "table-wrap" },
        h(
          "table",
          { class: "visits" },
          h(
            "thead",
            {},
            h(
              "tr",
              {},
              heads.map((t) => h("th", {}, t)),
            ),
          ),
          h("tbody", {}, data.visits.map(visitRow)),
        ),
      )
    : h(
        "p",
        { class: "empty" },
        "No visits in this data folder yet. Plug in the iPhone and press Sync from iPhone, or start the server with --data <folder> pointing at copied visits.",
      );
  const others = data.others.length
    ? h(
        "p",
        { class: "muted small" },
        `Also in the data folder (not visits): ${data.others.join(", ")}`,
      )
    : null;
  app.replaceChildren(
    syncBox,
    h(
      "section",
      { class: "card" },
      h(
        "div",
        { class: "section-head" },
        h("h1", {}, `Visits `, count(data.visits)),
        h("button", { type: "button", class: "secondary", onclick: () => route() }, "Refresh"),
      ),
      list,
      others,
    ),
  );
}

function visitRow(v) {
  const title =
    v.projectName ??
    v.address ??
    (v.counts?.files ? "Visit without a capture record" : "Empty visit");
  const sub = [
    v.address && v.address !== title ? v.address : null,
    v.dealId ? `Deal ${v.dealId}` : null,
  ]
    .filter(Boolean)
    .join(" · ");
  const tr = h(
    "tr",
    { class: v.counts?.files ? "clickable" : "clickable dim" },
    h(
      "td",
      { class: "nowrap" },
      fmtDate(v.date),
      h(
        "div",
        { class: "muted small" },
        v.dateSource === "visitedAt" ? "visit date" : `from ${v.dateSource ?? "?"}`,
      ),
    ),
    h(
      "td",
      { class: "visit" },
      h("a", { href: visitHref(v.id) }, title),
      sub ? h("div", { class: "muted small" }, sub) : null,
      h("div", { class: "mono small muted" }, v.id),
    ),
    // The labels show only on phone widths, where the table becomes stacked rows.
    h("td", { "data-label": "Operator" }, v.operator ?? "—"),
    h("td", { "data-label": "Areas" }, v.areas?.length ? v.areas.join(", ") : "—"),
    h(
      "td",
      { class: "nowrap" },
      `${v.counts?.files ?? 0} files`,
      h(
        "div",
        { class: "muted small" },
        fmtBytes(v.counts?.bytes ?? 0),
        v.counts?.photos ? ` · ${v.counts.photos} photos` : "",
      ),
    ),
    h(
      "td",
      { class: "status" },
      statusChips(v.status),
      v.error ? h("div", { class: "problem small" }, v.error) : null,
    ),
  );
  tr.addEventListener("click", (event) => {
    if (event.target.closest("a")) return;
    location.hash = visitHref(v.id);
  });
  return tr;
}

function renderSync(box, st) {
  const running = st.status === "running";
  const button = h(
    "button",
    { type: "button", class: "primary", disabled: running, onclick: () => startSync(box) },
    running ? "Syncing…" : "Sync from iPhone",
  );
  const head = h(
    "div",
    { class: "section-head" },
    h(
      "div",
      {},
      h("h2", {}, "iPhone"),
      h(
        "p",
        { class: "muted small" },
        "Copies FieldTestVisits from the Chapter Capture app on a connected iPhone into the data folder. Only new or changed files are copied; nothing is deleted.",
      ),
    ),
    button,
  );
  const tone = { done: "ok", partial: "warn", error: "bad", running: "info" }[st.status] ?? "muted";
  const parts = [h("p", { class: `sync-message ${tone}` }, st.message ?? "")];
  if (running) {
    if (st.total > 0) {
      parts.push(
        h("progress", {
          max: st.totalBytes || st.total,
          value: st.totalBytes ? st.doneBytes : st.done,
        }),
        h(
          "p",
          { class: "muted small" },
          `${st.done} of ${st.total} files · ${fmtBytes(st.doneBytes)} of ${fmtBytes(st.totalBytes)}`,
        ),
      );
    } else {
      parts.push(h("progress", {}));
    }
  }
  const facts = [];
  if (st.device) {
    const extra = [st.device.model, st.device.transport].filter(Boolean).join(", ");
    facts.push(`Phone: ${st.device.name}${extra ? ` (${extra})` : ""}`);
  }
  if (!running && st.status !== "idle" && Number.isFinite(st.copied)) {
    facts.push(`${st.copied} copied · ${st.skipped} up to date · ${st.failureCount ?? 0} failed`);
  }
  if (st.finishedAt) facts.push(`finished ${fmtDate(st.finishedAt)}`);
  if (facts.length) parts.push(h("p", { class: "muted small" }, facts.join(" · ")));
  if (st.failures?.length) {
    parts.push(
      h(
        "details",
        { class: "failures", open: st.failures.length <= 5 },
        h("summary", {}, `${st.failureCount ?? st.failures.length} failed`),
        h(
          "ul",
          {},
          st.failures.map((f) => h("li", {}, mono(f.path), ": ", f.error)),
        ),
      ),
    );
  }
  box.replaceChildren(head, ...parts);
}

async function startSync(box) {
  try {
    renderSync(box, await api("/api/sync", { method: "POST" }));
    pollSync(box);
  } catch (err) {
    renderSync(box, { status: "error", message: err.message, failures: [] });
  }
}

function pollSync(box) {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(async () => {
    if (!box.isConnected) return;
    let st;
    try {
      st = await api("/api/sync");
    } catch (err) {
      renderSync(box, { status: "error", message: err.message, failures: [] });
      return;
    }
    if (!box.isConnected) return;
    if (st.status === "running") {
      renderSync(box, st);
      pollSync(box);
    } else {
      route(); // Reload the list with whatever was copied; it shows the final sync state too.
    }
  }, 700);
}

// ---------------------------------------------------------------------------------------------
// Visit page

async function renderVisit(id, token) {
  app.replaceChildren(muted("Loading visit…"));
  const v = await api(`/api/visit?id=${enc(id)}`);
  if (token !== renderToken) return;
  const sum = v.summary;
  const r = v.record ?? {};
  document.title = `${sum.projectName ?? sum.folder} · Scan browser`;
  api("/api/status")
    .then((st) => setDataDir(st.dataDir))
    .catch(() => {});

  const device = r.device
    ? [
        r.device.model,
        r.device.osName ? `${r.device.osName} ${r.device.osVersion ?? ""}`.trim() : null,
        r.device.hasLidar === false ? "no LiDAR" : r.device.hasLidar ? "LiDAR" : null,
      ]
        .filter(Boolean)
        .join(" · ")
    : null;
  const header = h(
    "section",
    { class: "card" },
    h("a", { href: "#/", class: "back" }, "← All visits"),
    h("h1", {}, sum.projectName ?? sum.address ?? sum.folder),
    statusChips(sum.status),
    factList([
      [
        "Visit date",
        `${fmtDate(sum.date)}${sum.dateSource === "visitedAt" ? "" : ` (from ${sum.dateSource})`}`,
      ],
      ["Operator", sum.operator],
      ["Project", sum.projectName],
      ["Deal", sum.dealId],
      ["Address", sum.address],
      [
        "Address confirmed",
        r.address?.confirmedAt
          ? `${fmtDate(r.address.confirmedAt)}${r.address.confirmedOnSite ? " (on site)" : ""}`
          : null,
      ],
      ["Device", device],
      ["App", r.app ? `${r.app.version ?? "?"} (build ${r.app.build ?? "?"})` : null],
      ["Visit ID", sum.visitId],
      ["Folder", sum.id],
      ["Files", `${sum.counts.files} (${fmtBytes(sum.counts.bytes)})`],
      ["Capture record", v.recordPath],
    ]),
    v.record
      ? null
      : h(
          "p",
          { class: "muted small" },
          'No capture record yet: it is written when "Package ready" is built, so areas are shown by their area key.',
        ),
  );

  const sections = [];
  const toc = [];
  v.captures.forEach((c, index) => {
    const section = captureSection(c, `capture-${index}`, sum.id);
    sections.push(section);
    toc.push([`${c.label ?? c.areaKey}`, section]);
  });
  for (const [title, section] of visitWideSections(v)) {
    sections.push(section);
    toc.push([title, section]);
  }
  const nav = h(
    "nav",
    { class: "toc", "aria-label": "Sections" },
    toc.map(([title, section]) =>
      h(
        "button",
        {
          type: "button",
          class: "chip-button",
          onclick: () => section.scrollIntoView({ behavior: "smooth" }),
        },
        title,
      ),
    ),
  );
  if (v.captures.length === 0)
    sections.unshift(card("Captures", muted("No scans in this visit yet.")));
  app.replaceChildren(header, nav, ...sections);
}

function captureSection(c, id, visitId) {
  return h(
    "section",
    { class: "card capture", id },
    h(
      "div",
      { class: "section-head" },
      h(
        "div",
        {},
        h("h2", {}, c.label ?? c.areaKey, " ", h("span", { class: "muted" }, `area ${c.areaKey}`)),
        h("p", { class: "mono small muted" }, `capture ${c.captureId}`),
      ),
    ),
    factList([
      ["Mode", c.mode],
      ["Captured", c.capturedAt ? fmtDate(c.capturedAt) : null],
      ["Finished", c.finishedAt ? fmtDate(c.finishedAt) : null],
      ["In capture record", c.inRecord ? "yes" : "no (not built into a package yet)"],
    ]),
    c.raw.length === 0 && !c.exports && c.photos.every((p) => p.missing)
      ? h(
          "p",
          { class: "problem" },
          "None of this capture's files are in this copy: it is known only from the capture record or photo records.",
        )
      : null,
    h(
      "h3",
      {},
      "Plans ",
      h("span", { class: "h-note" }, "(rendered now with the current app code)"),
    ),
    floorplanBlock(visitId, c),
    h("h3", {}, "Room sketch"),
    sketchBlock(c),
    h("h3", {}, "Raw scan (originals) ", count(c.raw)),
    c.raw.length ? fileTable(c.raw) : muted("No raw originals for this capture."),
    h("h3", {}, "Exports ", count(c.exports?.files)),
    exportsBlock(c),
    h("h3", {}, "Photos ", count(c.photos)),
    photosBlock(c.photos),
  );
}

function exportsBlock(c) {
  if (!c.exports) {
    return muted('No exports yet: they are written when "Package ready" is built on the phone.');
  }
  const e = c.exports;
  // These files are what the phone wrote, not the current code (the Floorplan above is).
  const writtenBy = h(
    "p",
    { class: "muted small" },
    "Written on the phone by the app build that made the package",
    e.app ? ` (app ${e.app.version ?? "?"}, build ${e.app.build ?? "?"})` : "",
    ", so they show that build's plan code, not the current one.",
  );
  if (e.source === "package") {
    return h(
      "div",
      {},
      h(
        "p",
        { class: "muted small" },
        "From sealed package ",
        mono(e.packageId),
        e.sealedAt ? ` · sealed ${fmtDate(e.sealedAt)}` : "",
        " · no draft in this copy has this capture",
      ),
      writtenBy,
      fileTable(e.files),
    );
  }
  const older = c.olderExports.length
    ? h(
        "details",
        { class: "older" },
        h("summary", {}, `Older drafts (${c.olderExports.length})`),
        c.olderExports.map((o) => [
          h(
            "p",
            { class: "muted small" },
            "Draft ",
            mono(o.draftId),
            ` · built ${fmtDate(o.builtAt)}`,
          ),
          fileTable(o.files),
        ]),
      )
    : null;
  return h(
    "div",
    {},
    h(
      "p",
      { class: "muted small" },
      "From draft ",
      mono(e.draftId),
      ` · built ${fmtDate(e.builtAt)} · `,
      e.latest
        ? "the latest draft"
        : "not the latest draft (the latest has no files for this capture)",
    ),
    writtenBy,
    fileTable(e.files),
    older,
  );
}

function visitWideSections(v) {
  const out = [];
  out.push([
    "Field controls",
    card(
      "Field controls ",
      v.controls.length ? fileTable(v.controls) : muted("No field controls file."),
    ),
  ]);
  out.push([
    "Source register",
    card(
      "Source register",
      v.register
        ? [
            h(
              "p",
              { class: "muted small" },
              "From the latest draft ",
              mono(v.register.draftId),
              ". The manifest is written only into a sealed package (see below).",
            ),
            v.register.files.length
              ? fileTable(v.register.files)
              : muted("The latest draft has no source register files."),
          ]
        : muted('No source register yet: it is written when "Package ready" is built.'),
      v.olderRegisters.length
        ? h(
            "details",
            { class: "older" },
            h("summary", {}, `Older drafts (${v.olderRegisters.length})`),
            v.olderRegisters.map((o) => [
              h(
                "p",
                { class: "muted small" },
                "Draft ",
                mono(o.draftId),
                ` · built ${fmtDate(o.builtAt)}`,
              ),
              fileTable(o.files),
            ]),
          )
        : null,
    ),
  ]);
  out.push([
    "Photo records",
    card(
      "Photo records",
      v.photoRecords
        ? [
            h("p", { class: "muted small" }, `${v.photoRecords.count} records`),
            fileTable([v.photoRecords]),
          ]
        : muted("No photo-records.json."),
    ),
  ]);
  out.push([
    "Sealed packages",
    card(
      "Sealed packages ",
      v.packages.length ? v.packages.map(packageBlock) : muted("Nothing sealed yet."),
    ),
  ]);
  out.push([
    "Drafts",
    card(
      "Drafts ",
      v.drafts.length
        ? h(
            "div",
            { class: "table-wrap" },
            h(
              "table",
              { class: "data" },
              h(
                "thead",
                {},
                h(
                  "tr",
                  {},
                  ["Draft", "Built", "Files", "Size", ""].map((t) => h("th", {}, t)),
                ),
              ),
              h(
                "tbody",
                {},
                v.drafts.map((d) =>
                  h(
                    "tr",
                    {},
                    h("td", {}, mono(d.id)),
                    h("td", { class: "nowrap" }, fmtDate(d.builtAt)),
                    h("td", { class: "num" }, String(d.files)),
                    h("td", { class: "num nowrap" }, fmtBytes(d.bytes)),
                    h("td", {}, d.latest ? chip("built", "latest") : ""),
                  ),
                ),
              ),
            ),
          )
        : muted('No drafts: "Package ready" has not been built for this visit.'),
    ),
  ]);
  const otherFiles = [...v.other, ...v.draftOther];
  if (otherFiles.length || v.symlinks.length) {
    out.push([
      "Other files",
      card(
        "Other files ",
        h("p", { class: "muted small" }, "Files outside the expected layout."),
        otherFiles.length
          ? fileTable(otherFiles, { nameOf: (f) => f.path.split("/").slice(1).join("/") })
          : null,
        v.symlinks.length
          ? h("p", { class: "problem" }, `Symbolic links (not followed): ${v.symlinks.join(", ")}`)
          : null,
      ),
    ]);
  }
  return out;
}

function packageBlock(k) {
  const facts = [];
  if (k.manifest && !k.manifest.error) {
    facts.push(
      ["Sealed at", fmtDate(k.manifest.sealedAt)],
      ["Revision", k.manifest.revision],
      ["Manifest", `${k.manifest.files} files (${fmtBytes(k.manifest.bytes)})`],
    );
  } else {
    facts.push(["Manifest", k.manifest?.error ? `unreadable: ${k.manifest.error}` : "missing"]);
  }
  if (k.upload && !k.upload.error) {
    facts.push(
      ["Upload", `${k.upload.verified} of ${k.upload.files} files verified`],
      [
        "Phases",
        Object.entries(k.upload.phases)
          .map(([p, n]) => `${p} ${n}`)
          .join(", ") || "—",
      ],
      ["Station", k.upload.sealStatus ?? "not sealed with the station yet"],
      ["Rejected uploads", k.upload.rejected],
      ["Deal", k.upload.dealId],
    );
  } else {
    facts.push([
      "Upload state",
      k.upload?.error ? `unreadable: ${k.upload.error}` : "no upload-state.json",
    ]);
  }
  const groups = new Map();
  for (const f of k.files) {
    const g = f.group ?? "Other";
    if (!groups.has(g)) groups.set(g, []);
    groups.get(g).push(f);
  }
  return h(
    "div",
    { class: "package" },
    h("h3", {}, "Package ", mono(k.id)),
    factList(facts),
    k.files.length === 0
      ? h(
          "p",
          { class: "problem" },
          "The package folder has no files here. Sealed packages are read-only on the phone; a plain devicectl copy cannot fill them. Use Sync from iPhone to copy them file by file.",
        )
      : null,
    k.missing.length
      ? h(
          "p",
          { class: "problem" },
          `${k.missing.length} manifest files are not in the copied folder: ${k.missing.join(", ")}`,
        )
      : null,
    k.uploadState ? [h("h4", {}, "Upload state"), fileTable([k.uploadState])] : null,
    [...groups].map(([group, files]) => [
      h("h4", {}, group, " ", count(files)),
      fileTable(files, {
        pkg: true,
        nameOf: (f) => f.inPackage.split("/").slice(1).join("/") || f.name,
      }),
    ]),
  );
}

// ---------------------------------------------------------------------------------------------
// File tables and previews

// A capture's files carry a label: their path below the capture folder (subfolders included).
function fileTable(files, { pkg = false, nameOf = (f) => f.label || f.name } = {}) {
  // Fixed layout with set column widths, so a wide preview (a CSV table, a long text line)
  // scrolls inside its own row instead of widening the table.
  const heads = [
    ["Name", "col-name"],
    ["Size", "col-size"],
    ["Modified", "col-date"],
    ...(pkg
      ? [
          ["Role", "col-role"],
          ["Upload", "col-phase"],
        ]
      : []),
    ["", "col-actions"],
  ];
  const body = h("tbody");
  for (const f of files) {
    const cell = h("td", { colspan: heads.length, class: "preview-cell" });
    const previewRow = h("tr", { class: "preview-row", hidden: true }, cell);
    const toggle = h(
      "button",
      { type: "button", class: "link", "aria-expanded": "false" },
      "Preview",
    );
    let loaded = false;
    toggle.addEventListener("click", () => {
      const open = previewRow.hidden;
      previewRow.hidden = !open;
      toggle.textContent = open ? "Hide" : "Preview";
      toggle.setAttribute("aria-expanded", String(open));
      if (open && !loaded) {
        loaded = true;
        fillPreview(cell, f);
      }
    });
    body.append(
      h(
        "tr",
        {},
        h(
          "td",
          { class: "name" },
          mono(nameOf(f)),
          f.sizeMatches === false
            ? h("span", { class: "warn small" }, " size differs from the manifest")
            : null,
        ),
        h("td", { class: "num nowrap" }, fmtBytes(f.size)),
        h("td", { class: "nowrap" }, fmtDate(f.mtime)),
        pkg ? h("td", { class: "small", "data-label": "Role" }, f.role ?? "—") : null,
        pkg ? h("td", { class: "small", "data-label": "Upload" }, f.phase ?? "—") : null,
        h(
          "td",
          { class: "actions nowrap" },
          toggle,
          h("a", { href: fileUrl(f.path), target: "_blank", rel: "noopener" }, "Open"),
          h("a", { href: downloadUrl(f.path), download: f.name }, "Download"),
        ),
      ),
      previewRow,
    );
  }
  return h(
    "div",
    { class: "table-wrap" },
    h(
      "table",
      { class: "files" },
      h(
        "thead",
        {},
        h(
          "tr",
          {},
          heads.map(([t, cls]) => h("th", { class: cls }, t)),
        ),
      ),
      body,
    ),
  );
}

async function fillPreview(cell, f) {
  cell.replaceChildren(muted("Loading preview…"));
  try {
    let node;
    if (f.kind === "pdf") {
      node = h("iframe", { src: fileUrl(f.path), class: "pdf", title: f.name });
    } else if (f.kind === "image" || f.kind === "svg") {
      // SVG goes in an <img>, which never runs scripts or loads anything else.
      node = h("img", { src: fileUrl(f.path), alt: f.name, class: `preview-img ${f.kind}` });
    } else if (f.kind === "heic") {
      node = h("img", { src: photoUrl(f, 1600), alt: f.name, class: "preview-img" });
    } else if (f.kind === "glb") {
      node = modelPreview(f);
    } else {
      node = renderPreviewData(await api(`/api/preview?path=${enc(f.path)}`));
    }
    cell.replaceChildren(node);
  } catch (err) {
    cell.replaceChildren(errorBox(err.message));
  }
}

function dataTable(table) {
  return h(
    "div",
    { class: "table-wrap" },
    h(
      "table",
      { class: "data" },
      h(
        "thead",
        {},
        h(
          "tr",
          {},
          table.columns.map((c) => h("th", {}, c)),
        ),
      ),
      h(
        "tbody",
        {},
        table.rows.map((row) =>
          h(
            "tr",
            {},
            row.map((value) => h("td", {}, value)),
          ),
        ),
      ),
    ),
  );
}

function renderPreviewData(p) {
  return h(
    "div",
    { class: "preview" },
    (p.problems ?? []).map((text) => errorBox(text)),
    p.facts?.length ? factList(p.facts) : null,
    (p.notes ?? []).map((text) => h("p", { class: "muted small" }, text)),
    p.table ? dataTable(p.table) : null,
    p.table2 ? dataTable(p.table2) : null,
    p.kind === "json" ? jsonTree(p.json) : null,
    typeof p.text === "string" ? h("pre", { class: "text" }, p.text) : null,
  );
}

function inlinePreview(value) {
  const limit = 90;
  let out = "";
  const walk = (v) => {
    if (out.length > limit) return;
    if (Array.isArray(v)) {
      out += "[";
      v.some((x, i) => {
        if (i) out += ", ";
        walk(x);
        return out.length > limit;
      });
      out += "]";
    } else if (v && typeof v === "object") {
      out += "{";
      Object.entries(v).some(([k, x], i) => {
        if (i) out += ", ";
        out += `${k}: `;
        walk(x);
        return out.length > limit;
      });
      out += "}";
    } else {
      out += typeof v === "string" ? JSON.stringify(v) : String(v);
    }
  };
  walk(value);
  return out.length > limit ? `${out.slice(0, limit)}…` : out;
}

function jsonValue(v) {
  if (typeof v === "string") return h("span", { class: "j-str" }, JSON.stringify(v));
  if (typeof v === "number") return h("span", { class: "j-num" }, String(v));
  if (typeof v === "boolean") return h("span", { class: "j-bool" }, String(v));
  return h("span", { class: "j-null" }, "null");
}

/** Collapsible JSON; children are built only when a node is first opened. */
function jsonNode(key, value, depth) {
  const keyEl =
    key === null
      ? null
      : h("span", { class: typeof key === "number" ? "j-idx" : "j-key" }, `${key}: `);
  if (value === null || typeof value !== "object")
    return h("div", { class: "j-leaf" }, keyEl, jsonValue(value));
  const isArray = Array.isArray(value);
  const entries = isArray ? value.map((v, i) => [i, v]) : Object.entries(value);
  const details = h(
    "details",
    { class: "j-node" },
    h(
      "summary",
      {},
      keyEl,
      h("span", { class: "j-brace" }, isArray ? `[${entries.length}]` : `{${entries.length}}`),
      " ",
      h("span", { class: "j-peek" }, inlinePreview(value)),
    ),
  );
  let filled = false;
  const fill = () => {
    if (filled) return;
    filled = true;
    const box = h("div", { class: "j-children" });
    const addPage = (start) => {
      const end = Math.min(entries.length, start + JSON_PAGE);
      for (let i = start; i < end; i += 1)
        box.append(jsonNode(entries[i][0], entries[i][1], depth + 1));
      if (end < entries.length) {
        const more = h(
          "button",
          { type: "button", class: "link" },
          `Show ${Math.min(JSON_PAGE, entries.length - end)} more (${entries.length - end} left)`,
        );
        more.addEventListener("click", () => {
          more.remove();
          addPage(end);
        });
        box.append(more);
      }
    };
    addPage(0);
    details.append(box);
  };
  details.addEventListener("toggle", () => details.open && fill());
  if (depth < 1) {
    details.open = true;
    fill();
  }
  return details;
}

function jsonTree(value) {
  return h("div", { class: "json" }, jsonNode(null, value, 0));
}

let modelViewerLoading = null;
function loadModelViewer() {
  if (customElements.get("model-viewer")) return Promise.resolve();
  modelViewerLoading ??= new Promise((resolve, reject) => {
    const script = h("script", {
      type: "module",
      src: MODEL_VIEWER_URL,
      integrity: MODEL_VIEWER_SRI,
      crossorigin: "anonymous",
      referrerpolicy: "no-referrer",
    });
    script.addEventListener("load", () => customElements.whenDefined("model-viewer").then(resolve));
    script.addEventListener("error", () => {
      modelViewerLoading = null;
      script.remove();
      reject(
        new Error(
          "The 3D viewer (@google/model-viewer from cdn.jsdelivr.net) could not be loaded: offline, or the file did not match its pinned hash. Download the GLB instead.",
        ),
      );
    });
    document.head.append(script);
  });
  return modelViewerLoading;
}

function modelPreview(f) {
  const box = h("div", { class: "model" }, muted("Loading the 3D viewer…"));
  loadModelViewer()
    .then(() =>
      box.replaceChildren(
        h("model-viewer", {
          src: fileUrl(f.path),
          alt: f.name,
          "camera-controls": true,
          "interaction-prompt": "none",
          "shadow-intensity": "0",
          exposure: "1",
        }),
        h(
          "p",
          { class: "muted small" },
          "Drag to orbit, scroll to zoom. Viewer: @google/model-viewer 3.5.0 from cdn.jsdelivr.net.",
        ),
      ),
    )
    .catch((err) => box.replaceChildren(errorBox(err.message)));
  return box;
}

// ---------------------------------------------------------------------------------------------
// Photos

function photoTitle(p) {
  const labels = p.record?.labels ?? {};
  return (
    [labels.room, labels.direction, labels.subject].filter(Boolean).join(" · ") ||
    p.file?.name ||
    "Photo"
  );
}

function photosBlock(photos) {
  if (!photos.length) return muted("No photos for this capture.");
  return h("div", { class: "photos" }, photos.map(photoCard));
}

function photoCard(p) {
  const labels = p.record?.labels ?? {};
  const title = photoTitle(p);
  const extra = Object.entries(labels)
    .filter(([k]) => !["room", "direction", "subject", "takenAt"].includes(k))
    .map(([k, v]) => `${k}: ${typeof v === "object" ? JSON.stringify(v) : v}`);
  const when = [
    labels.takenAt ? fmtDate(labels.takenAt) : null,
    p.record?.sequence ? `#${p.record.sequence}` : null,
  ]
    .filter(Boolean)
    .join(" · ");
  const caption = h(
    "figcaption",
    {},
    h("strong", {}, title),
    when ? h("div", { class: "muted small" }, when) : null,
    extra.length ? h("div", { class: "small" }, extra.join(" · ")) : null,
  );
  if (p.missing) {
    return h(
      "figure",
      { class: "photo" },
      h("div", { class: "thumb placeholder" }, "File missing"),
      caption,
      h("div", { class: "small mono muted" }, p.record?.path ?? ""),
    );
  }
  const img = h("img", { src: photoUrl(p.file, 480), alt: title, loading: "lazy" });
  img.addEventListener("error", () =>
    img.replaceWith(h("div", { class: "placeholder" }, "Could not convert")),
  );
  return h(
    "figure",
    { class: "photo" },
    h("button", { type: "button", class: "thumb", onclick: () => openPhoto(p) }, img),
    caption,
    h(
      "div",
      { class: "small" },
      h(
        "a",
        { href: downloadUrl(p.file.path), download: p.file.name },
        p.file.label || p.file.name,
      ),
      ` · ${fmtBytes(p.file.size)}`,
    ),
    p.record ? null : h("div", { class: "warn small" }, "Not in photo-records.json"),
    p.record && Number.isFinite(p.record.bytes) && p.record.bytes !== p.file.size
      ? h(
          "div",
          { class: "warn small" },
          `Size differs from the record (${fmtBytes(p.record.bytes)})`,
        )
      : null,
  );
}

function openPhoto(p) {
  const title = photoTitle(p);
  lightbox.replaceChildren(
    h(
      "div",
      { class: "lightbox-head" },
      h("strong", {}, title),
      h("button", { type: "button", class: "secondary", onclick: () => lightbox.close() }, "Close"),
    ),
    h("img", { src: photoUrl(p.file, 2400), alt: title }),
    h(
      "p",
      { class: "small" },
      h("a", { href: downloadUrl(p.file.path), download: p.file.name }, `Download ${p.file.name}`),
      " · ",
      h(
        "a",
        { href: photoUrl(p.file, 2400), download: p.file.name.replace(/\.[^.]+$/, ".jpg") },
        "Download JPEG",
      ),
      " · ",
      mono(p.file.path),
    ),
  );
  lightbox.showModal();
}

lightbox.addEventListener("click", (event) => {
  if (event.target === lightbox) lightbox.close();
});

// ---------------------------------------------------------------------------------------------
// Plans: the plan sheet (the Tabloid page the package carries and the phone shows first) and the
// colour Floorplan (the phone's "Colour floorplan"), rendered by the server with the current app
// code (tools/plan-render, one render for both). The server builds the renderer on first need, so
// the page asks once with start=1 and then polls until the plans are ready or have failed.

const FLOORPLAN_POLL_MS = 1000;
const PAGE_NAMES = { letterLandscape: "Letter landscape page", square: "10 in square page" };

function floorplanBlock(visitId, c) {
  const sources = c.floorplan?.sources ?? [];
  if (!sources.length) {
    return muted(
      "No roomplan.json or capture-model.json for this capture, so there are no plans to draw.",
    );
  }
  let current = sources[0].id;
  let generation = 0;
  let timer = 0;
  const note = h("p", { class: "muted small" });
  const box = h("div", { class: "floorplan-box" });
  const buttons = sources.map((src) =>
    h(
      "button",
      {
        type: "button",
        class: "segment",
        "aria-pressed": String(src.id === current),
        title: src.detail,
        onclick: () => {
          if (src.id === current) return;
          current = src.id;
          buttons.forEach((b, i) =>
            b.setAttribute("aria-pressed", String(sources[i].id === current)),
          );
          load(true);
        },
      },
      src.label,
    ),
  );
  const switcher =
    sources.length > 1
      ? h(
          "div",
          { class: "segmented", role: "group", "aria-label": "Draw the plans from" },
          h("span", { class: "muted small" }, "Draw from"),
          buttons,
        )
      : null;
  const wrap = h("div", { class: "floorplan" }, switcher, note, box);

  const retry = () =>
    h("button", { type: "button", class: "secondary", onclick: () => load(true) }, "Try again");
  // Redrawn only when the state changes, so the spinner turns smoothly between polls.
  let working = "";
  const showWorking = (st) => {
    const state = st ? `${st.status}\n${st.message ?? ""}` : "start";
    if (state === working) return;
    working = state;
    box.replaceChildren(
      h(
        "div",
        { class: "working", role: "status" },
        h("span", { class: "spinner", "aria-hidden": "true" }),
        h(
          "div",
          {},
          h("strong", {}, "Rendering the plans…"),
          st?.status === "building" ? h("p", { class: "muted small" }, st.message) : null,
        ),
      ),
    );
  };
  const show = (...nodes) => {
    working = "";
    box.replaceChildren(...nodes);
  };

  function load(start) {
    const gen = ++generation;
    clearTimeout(timer);
    const source = sources.find((x) => x.id === current);
    note.textContent = `From ${source.detail}.`;
    if (start) showWorking(null);
    const url = `/api/floorplan?visit=${enc(visitId)}&capture=${enc(c.key)}&source=${enc(current)}${start ? "&start=1" : ""}`;
    api(url)
      .then((st) => {
        if (gen !== generation || !wrap.isConnected) return;
        if (st.status === "ready") {
          show(...floorplanPage(st, c));
        } else if (st.status === "error") {
          show(h("pre", { class: "problem" }, st.message), retry());
        } else {
          showWorking(st);
          timer = setTimeout(() => load(false), FLOORPLAN_POLL_MS);
        }
      })
      .catch((err) => {
        if (gen === generation && wrap.isConnected) show(errorBox(err.message), retry());
      });
  }
  load(true);
  return wrap;
}

function floorplanPage(st, c) {
  const url = (name, download) =>
    `/api/floorplan-file?key=${enc(st.key)}&name=${name}${download ? "&download=1" : ""}`;
  const s = st.summary ?? {};
  const name = c.label ?? c.areaKey;
  const rendered = st.renderedAt ? `rendered ${fmtDate(st.renderedAt)}` : null;

  // The plan sheet: Tabloid 11 x 17 in, always imperial, its title block from the capture
  // record (or "not recorded" where there is none).
  const sheet = s.planSheet ?? {};
  const sheetScale = Number.isFinite(sheet.scaleDenominator)
    ? `1:${Math.round(sheet.scaleDenominator)} at 11 x 17 in`
    : null;
  const titleBlock =
    sheet.titleBlock === "capture record"
      ? "title block from the capture record"
      : sheet.titleBlock
        ? `title block "not recorded" (${sheet.note ?? "no capture record"})`
        : null;
  const sheetFacts = [
    sheetScale,
    sheet.isClipped ? "cut at the frame (larger than the sheet)" : null,
    titleBlock,
    rendered,
  ]
    .filter(Boolean)
    .join(" · ");

  // The colour Floorplan.
  const rooms = Number.isFinite(s.rooms) ? `${s.rooms} room${s.rooms === 1 ? "" : "s"}` : null;
  const scale = Number.isFinite(s.scaleDenominator)
    ? `1:${Math.round(s.scaleDenominator)} on a ${PAGE_NAMES[s.page] ?? "page"}`
    : null;
  const units = st.options?.units === "metric" ? "metres" : "feet and inches";
  const facts = [s.totalText, rooms, scale, units].filter(Boolean).join(" · ");

  const open = (file, label) =>
    h("a", { href: url(file), target: "_blank", rel: "noopener" }, label);
  const save = (file, label) => h("a", { href: url(file, true), download: "" }, label);
  return [
    h("h4", { class: "plan-title" }, "Plan sheet"),
    h(
      "a",
      {
        href: url("plan-sheet.pdf"),
        target: "_blank",
        rel: "noopener",
        class: "floorplan-page plan-sheet-page",
        title: "Open the PDF",
      },
      h("img", { src: url("plan-sheet.png"), alt: `Plan sheet of ${name}` }),
    ),
    h("p", { class: "small" }, sheetFacts),
    h(
      "p",
      { class: "links small" },
      open("plan-sheet.pdf", "Open PDF"),
      save("plan-sheet.pdf", "Download plan-sheet.pdf"),
      open("plan-sheet.png", "Open PNG"),
      save("plan-sheet.png", "Download PNG (200 dpi)"),
    ),
    h("h4", { class: "plan-title" }, "Colour floorplan"),
    h(
      "a",
      {
        href: url("floorplan.pdf"),
        target: "_blank",
        rel: "noopener",
        class: "floorplan-page",
        title: "Open the PDF",
      },
      h("img", { src: url("floorplan.png"), alt: `Colour floorplan of ${name}` }),
    ),
    h("p", { class: "small" }, facts),
    h(
      "p",
      { class: "links small" },
      open("floorplan.pdf", "Open PDF"),
      save("floorplan.pdf", "Download PDF"),
      open("floorplan.svg", "Open SVG"),
      save("floorplan.svg", "Download SVG"),
      save("floorplan.png", "Download PNG (200 dpi)"),
    ),
  ];
}

// ---------------------------------------------------------------------------------------------
// Room sketch: top-down SVG of capture-model.json (plan axes x and z; SVG y = z, so plan up is −z),
// in the Floorplan's palette: rooms filled by type, warm charcoal walls.

/** Room fills by room type, as on the Floorplan (PlanExport FloorPlanStyle.roomFill). */
const ROOM_FILLS = {
  bedroom: "#EDEEE5",
  living_room: "#F8F0E5",
  dining_room: "#F6ECE0",
  kitchen: "#F5E6DB",
  bathroom: "#E8ECF1",
  closet: "#EFE9E1",
  hallway: "#F6F1EA",
  laundry: "#EBEEF2",
  office: "#F2ECE7",
  utility: "#EFEDEA",
  other: "#F5F2EE",
};

/** Room type from a label, for models written before rooms had a type (as the Floorplan does). */
const LABEL_TYPES = [
  ["bedroom", ["bed"]],
  ["bathroom", ["bath", "toilet", "shower", "wc"]],
  ["kitchen", ["kitchen"]],
  ["living_room", ["living", "lounge", "family"]],
  ["dining_room", ["dining"]],
  ["closet", ["closet", "wardrobe", "pantry"]],
  ["hallway", ["hall", "corridor", "entry", "foyer"]],
  ["laundry", ["laundry"]],
  ["office", ["office", "study"]],
];

function roomFill(room) {
  if (room.type && Object.hasOwn(ROOM_FILLS, room.type)) return ROOM_FILLS[room.type];
  const text = String(room.label ?? "").toLowerCase();
  const match = LABEL_TYPES.find(([, words]) => words.some((w) => text.includes(w)));
  return ROOM_FILLS[match ? match[0] : "other"];
}

function sketchBlock(c) {
  if (!c.sketchPath) {
    const fromRaw = c.floorplan?.sources?.some((x) => x.id === "roomplan");
    return muted(
      `No capture-model.json yet (no export), so there is no sketch.${fromRaw ? " The plans above are drawn from the raw scan." : ""}`,
    );
  }
  const box = h("div", { class: "sketch-box" }, muted("Drawing…"));
  api(`/api/sketch?path=${enc(c.sketchPath)}`)
    .then((data) => box.replaceChildren(...renderSketch(data).filter(Boolean)))
    .catch((err) => box.replaceChildren(errorBox(err.message)));
  return box;
}

function renderSketch(d) {
  const source = h("p", { class: "muted small" }, "From ", mono(d.path));
  if (!d.bounds) return [muted("The capture model has no rooms or walls to draw."), source];
  const pad = 0.9;
  const minX = d.bounds.minX - pad;
  const minZ = d.bounds.minZ - pad;
  const width = d.bounds.maxX - d.bounds.minX + 2 * pad;
  const height = d.bounds.maxZ - d.bounds.minZ + 2 * pad;
  const font = Math.min(0.42, Math.max(0.14, Math.max(width, height) / 48));
  const svg = s("svg", {
    viewBox: `${minX} ${minZ} ${width} ${height}`,
    class: "sketch",
    role: "img",
    "aria-label": `Top-down sketch of ${d.label ?? "the capture"}`,
  });

  const rooms = s("g", { class: "rooms" });
  for (const room of d.rooms) {
    rooms.append(
      s(
        "polygon",
        {
          points: room.polygon.map(([x, z]) => `${x},${z}`).join(" "),
          class: "room",
          fill: roomFill(room),
        },
        s("title", {}, `${room.label}: ${fmtNum(room.areaM2)} m² (${fmtNum(room.areaFt2, 1)} ft²)`),
      ),
    );
  }
  const walls = s("g", { class: "walls" });
  for (const w of d.walls) {
    walls.append(
      s(
        "line",
        { x1: w.a[0], y1: w.a[1], x2: w.b[0], y2: w.b[1], class: "wall" },
        s(
          "title",
          {},
          `${w.id}: ${fmtNum(w.lengthM)} m${w.roomIds.length ? ` · rooms ${w.roomIds.join(", ")}` : ""}`,
        ),
      ),
    );
  }
  const openings = s("g", { class: "openings" });
  for (const o of d.openings) {
    const state = o.isOpen === true ? " (open)" : o.isOpen === false ? " (closed)" : "";
    const ends = { x1: o.a[0], y1: o.a[1], x2: o.b[0], y2: o.b[1] };
    openings.append(
      s(
        "line",
        { ...ends, class: `opening-${o.kind}` },
        s("title", {}, `${o.kind} ${o.id}${state}: ${fmtNum(o.widthM)} m wide on ${o.wallId}`),
      ),
    );
    // A window reads as the drafting double line: a pale core inside its grey edges.
    if (o.kind === "window") openings.append(s("line", { ...ends, class: "window-core" }));
  }
  const labels = s("g", { class: "labels", "font-size": font });
  for (const room of d.rooms) {
    const [x, z] = room.labelAt;
    labels.append(
      s(
        "text",
        { x, y: z, "text-anchor": "middle" },
        s("tspan", { x, dy: `${-0.2}em`, class: "room-name" }, room.label),
        s(
          "tspan",
          { x, dy: "1.25em", class: "room-area" },
          `${fmtNum(room.areaM2, 1)} m² · ${fmtNum(room.areaFt2, 0)} ft²`,
        ),
      ),
    );
  }
  // 1 m scale bar (bottom left) and axis arrows (top right).
  const sx = minX + 0.3;
  const sz = minZ + height - 0.35;
  const scale = s(
    "g",
    { class: "scale", "font-size": font * 0.85 },
    s("line", { x1: sx, y1: sz, x2: sx + 1, y2: sz }),
    s("line", { x1: sx, y1: sz - 0.08, x2: sx, y2: sz + 0.08 }),
    s("line", { x1: sx + 1, y1: sz - 0.08, x2: sx + 1, y2: sz + 0.08 }),
    s("text", { x: sx + 0.5, y: sz - 0.14, "text-anchor": "middle" }, "1 m"),
  );
  const ax = minX + width - 0.95;
  const az = minZ + 0.3;
  const axes = s(
    "g",
    { class: "axes", "font-size": font * 0.85 },
    s("line", { x1: ax, y1: az, x2: ax + 0.6, y2: az }),
    s("line", { x1: ax, y1: az, x2: ax, y2: az + 0.6 }),
    s("text", { x: ax + 0.66, y: az + 0.06 }, "x"),
    s("text", { x: ax - 0.04, y: az + 0.85, "text-anchor": "middle" }, "z"),
  );
  svg.append(rooms, walls, openings, labels, scale, axes);

  const t = d.totals;
  const legend = h(
    "div",
    { class: "legend" },
    [
      ["wall", "Wall"],
      ["door", "Door"],
      ["window", "Window"],
      ["opening", "Opening"],
    ].map(([k, label]) => h("span", {}, h("i", { class: `swatch ${k}` }), label)),
    h(
      "span",
      { class: "muted" },
      "Axes: x right, z down (plan up is −z). Hover a room, wall or opening for details.",
    ),
  );
  const roomTable = dataTable({
    columns: ["Room", "Type", "Area m²", "Area ft²", "Height", "Corners"],
    rows: [
      ...d.rooms.map((r) => [
        r.label,
        r.type ? `${r.type.replaceAll("_", " ")}${r.typeSource ? ` (${r.typeSource})` : ""}` : "—",
        fmtNum(r.areaM2),
        fmtNum(r.areaFt2, 1),
        r.heightM ? `${fmtNum(r.heightM)} m` : "—",
        String(r.polygon.length),
      ]),
      ["Total", "", fmtNum(t.areaM2), fmtNum(t.areaFt2, 1), "", ""],
    ],
  });
  const summary = h(
    "p",
    { class: "small" },
    `${t.rooms} room${t.rooms === 1 ? "" : "s"} · ${t.walls} walls · ${t.doors} doors · ${t.windows} windows · ${t.openings} openings`,
  );
  const unplaced = d.unplaced.length
    ? errorBox(`Not drawn (wall not found or no size): ${d.unplaced.join(", ")}`)
    : null;
  return [h("div", { class: "sketch-frame" }, svg), legend, summary, unplaced, roomTable, source];
}

window.addEventListener("hashchange", route);
route();

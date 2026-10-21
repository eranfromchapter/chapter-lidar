"use client";

// The Files card of the package page (web-review §6.4.6): every package file with role, size,
// SHA-256, HUB state and download, filtered by floor, role group and text; photos grouped per
// capture; the first eight rows until "Show all". The rows come from the server with app URLs
// only (download routes); nothing is signed here. ?file= (a deep link from the HUB) expands the
// list, opens the photo group holding the file and scrolls to its row.

import { Fragment, useMemo, useState, type ReactNode } from "react";
import { Badge } from "@/components/hub/Badge";
import { Button } from "@/components/hub/Button";
import { Card } from "@/components/hub/Card";
import { Select } from "@/components/hub/Select";
import { TextField } from "@/components/hub/TextField";
import { Phrases } from "@/components/Phrases";
import { ScrollToTarget } from "@/components/ScrollToTarget";
import {
  COLLAPSED_ROWS,
  fileCount,
  filterRows,
  NO_FILTERS,
  rowHolding,
  type FileFilters,
  type FileRowView,
} from "@/lib/files-view";

export const TARGET_ROW_ID = "file-target";

export interface FilesCardProps {
  readonly rows: readonly FileRowView[];
  readonly totalFiles: number;
  readonly floorOptions: readonly { value: string; label: string }[];
  readonly roleOptions: readonly { value: string; label: string }[];
  /** Path from ?file=, highlighted and scrolled into view. */
  readonly targetPath?: string;
}

function HubCell({ row }: { readonly row: FileRowView }) {
  return row.hub === null ? (
    <span className="text-13 text-muted">—</span>
  ) : (
    <Badge tone={row.hub.tone}>{row.hub.text}</Badge>
  );
}

function FileRow({
  row,
  child = false,
  targetPath,
  action,
}: {
  readonly row: FileRowView;
  readonly child?: boolean;
  readonly targetPath: string | undefined;
  readonly action?: ReactNode;
}) {
  const isTarget = targetPath !== undefined && row.path === targetPath;
  return (
    <tr
      id={isTarget ? TARGET_ROW_ID : undefined}
      className={isTarget ? "is-target" : undefined}
      aria-current={isTarget ? "true" : undefined}
      data-path={row.path}
      data-kind={row.kind}
    >
      <td className={child ? "hub-table__child" : undefined}>
        <span className="hub-cell-title" title={row.path}>
          <Phrases text={row.name} separator=" / " />
        </span>
      </td>
      <td>{row.role}</td>
      <td className="nowrap">{row.size}</td>
      <td className="hub-cell-sha nowrap">
        {row.shaFull === undefined ? row.sha : <span title={row.shaFull}>{row.sha}</span>}
      </td>
      <td>
        <HubCell row={row} />
      </td>
      <td className="hub-table__action">
        {action ??
          (row.download === undefined ? (
            <span className="text-13 text-muted">Not verified</span>
          ) : (
            <Button
              variant="ghost"
              size="sm"
              href={row.download}
              rel="nofollow"
              aria-label={`Download ${row.name}`}
            >
              Download
            </Button>
          ))}
      </td>
    </tr>
  );
}

export function FilesCard({
  rows,
  totalFiles,
  floorOptions,
  roleOptions,
  targetPath,
}: FilesCardProps) {
  const target = targetPath === undefined ? undefined : rowHolding(rows, targetPath);
  const [filters, setFilters] = useState<FileFilters>(NO_FILTERS);
  const [showAll, setShowAll] = useState(target !== undefined);
  const [open, setOpen] = useState<ReadonlySet<string>>(
    () => new Set(target?.kind === "photoGroup" ? [target.key] : []),
  );
  const filtered = useMemo(() => filterRows(rows, filters), [rows, filters]);
  const visible = showAll ? filtered : filtered.slice(0, COLLAPSED_ROWS);
  const filtering = filters.floor !== "all" || filters.role !== "all" || filters.text.trim() !== "";
  const count = filtering ? fileCount(filtered) : totalFiles;

  const toggle = (key: string) =>
    setOpen((current) => {
      const next = new Set(current);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });

  return (
    <Card padding="none" table labelledBy="files-title" id="files">
      <div className="table-head table-head--files">
        <h3 className="card-title" id="files-title">
          Files · {totalFiles}
        </h3>
        <div className="table-head__controls">
          <Select
            id="files-floor"
            ariaLabel="Floor"
            fullWidth={false}
            width={140}
            options={floorOptions}
            value={filters.floor}
            onChange={(event) => setFilters({ ...filters, floor: event.target.value })}
          />
          <Select
            id="files-role"
            ariaLabel="Role"
            fullWidth={false}
            width={160}
            options={roleOptions}
            value={filters.role}
            onChange={(event) => setFilters({ ...filters, role: event.target.value })}
          />
          <TextField
            id="files-search"
            type="search"
            ariaLabel="Search files"
            placeholder="Search files"
            fullWidth={false}
            width={200}
            value={filters.text}
            onChange={(event) => setFilters({ ...filters, text: event.target.value })}
          />
        </div>
      </div>
      <div className="hub-card__scroll">
        <table className="hub-table hub-table--compact">
          <thead>
            <tr>
              <th scope="col">File</th>
              <th scope="col">Role</th>
              <th scope="col">Size</th>
              <th scope="col">SHA-256</th>
              <th scope="col">In the HUB</th>
              <th scope="col">
                <span className="visually-hidden">Download</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {visible.length === 0 ? (
              <tr>
                <td colSpan={6} className="hub-table__message">
                  No files match these filters.{" "}
                  <Button variant="ghost" size="sm" onClick={() => setFilters(NO_FILTERS)}>
                    Clear filters
                  </Button>
                </td>
              </tr>
            ) : (
              visible.map(({ row, matchedChildren }) => {
                if (row.kind !== "photoGroup") {
                  return <FileRow key={row.key} row={row} targetPath={targetPath} />;
                }
                const expanded = matchedChildren !== undefined || open.has(row.key);
                const children = matchedChildren ?? row.children ?? [];
                return (
                  <Fragment key={row.key}>
                    <FileRow
                      row={row}
                      targetPath={targetPath}
                      action={
                        <Button
                          variant="ghost"
                          size="sm"
                          aria-expanded={expanded}
                          onClick={() => toggle(row.key)}
                        >
                          {expanded ? "Hide photos" : "Show photos"}
                        </Button>
                      }
                    />
                    {expanded
                      ? children.map((photo) => (
                          <FileRow key={photo.key} row={photo} child targetPath={targetPath} />
                        ))
                      : null}
                  </Fragment>
                );
              })
            )}
          </tbody>
        </table>
      </div>
      <div className="files-footer">
        <span className="files-footer__note">
          Files over 45 MB stay in Chapter&apos;s storage and are linked from the HUB. Compare a
          download with its SHA-256 fingerprint.
        </span>
        {filtered.length > COLLAPSED_ROWS ? (
          <Button variant="ghost" size="sm" onClick={() => setShowAll(!showAll)}>
            {showAll ? "Show fewer files" : `Show all ${count} files`}
          </Button>
        ) : null}
      </div>
      {target !== undefined ? <ScrollToTarget targetId={TARGET_ROW_ID} /> : null}
    </Card>
  );
}

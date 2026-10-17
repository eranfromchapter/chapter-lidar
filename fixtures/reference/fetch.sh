#!/usr/bin/env bash
# Fetch real past intake packages from SharePoint into a local, gitignored folder.
#
# Usage (from the repository root):
#   CHAPTER_SHAREPOINT_SITE=<library base URL> CHAPTER_SHAREPOINT_TOKEN=<token> \
#     bash fixtures/reference/fetch.sh <reference-id> <sharepoint-folder-path>
#
#   CHAPTER_SHAREPOINT_SITE   https:// base URL of the document library (Microsoft Graph drive),
#                             for example https://graph.microsoft.com/v1.0/drives/<drive-id>
#   CHAPTER_SHAREPOINT_TOKEN  Bearer token for that library. Never printed, logged or saved.
#
# The folder path is given on the command line and is never stored in git.
# Files are written to fixtures/reference/.downloads/<reference-id>/ with a SHA256SUMS file.
# Nothing here is committed. The test suite does not run this script.
set -euo pipefail

fail() {
  echo "fetch.sh: $1" >&2
  exit "${2:-1}"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Reads one Graph children page on stdin. Prints "FILE<TAB>name<TAB>url" for each file,
# then "NEXT<TAB>url" when another page exists. Exits 1 on anything unexpected.
parse_page() {
  node -e '
    let raw = "";
    process.stdin.on("data", (chunk) => (raw += chunk));
    process.stdin.on("end", () => {
      let page;
      try {
        page = JSON.parse(raw);
      } catch (err) {
        console.error("fetch.sh: the SharePoint listing was not valid JSON");
        process.exit(1);
      }
      for (const item of page.value || []) {
        if (!item.file) continue;
        const name = String(item.name || "");
        const url = String(item["@microsoft.graph.downloadUrl"] || "");
        const unsafe = !name || name.includes("/") || name.includes("\\") ||
          name.startsWith(".") || /[\t\n\r]/.test(name);
        if (unsafe || !url.startsWith("https://")) {
          console.error("fetch.sh: refusing an item with an unsafe or incomplete name or URL");
          process.exit(1);
        }
        console.log(["FILE", name, url].join("\t"));
      }
      const next = page["@odata.nextLink"];
      if (next) {
        if (!String(next).startsWith("https://")) {
          console.error("fetch.sh: refusing a non-HTTPS next page link");
          process.exit(1);
        }
        console.log(["NEXT", next].join("\t"));
      }
    });
  '
}

if [[ $# -ne 2 ]]; then
  fail "usage: fetch.sh <reference-id> <sharepoint-folder-path>" 2
fi

ref_id="$1"
remote_path="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! "${ref_id}" =~ ^ref-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  fail "invalid reference id '${ref_id}'" 2
fi
if [[ ! -f "${script_dir}/${ref_id}.json" ]]; then
  fail "no manifest for '${ref_id}' in fixtures/reference/" 2
fi
if [[ -z "${remote_path}" || "${remote_path}" == /* ]]; then
  fail "the SharePoint folder path must be non-empty and relative to the library root" 2
fi

if [[ -z "${CHAPTER_SHAREPOINT_SITE:-}" ]]; then
  fail "CHAPTER_SHAREPOINT_SITE is not set. Nothing was fetched." 3
fi
if [[ -z "${CHAPTER_SHAREPOINT_TOKEN:-}" ]]; then
  fail "CHAPTER_SHAREPOINT_TOKEN is not set. Nothing was fetched." 3
fi
if [[ "${CHAPTER_SHAREPOINT_SITE}" != https://* ]]; then
  fail "CHAPTER_SHAREPOINT_SITE must be an https:// URL. Nothing was fetched." 3
fi

encoded_path="$(node -e 'process.stdout.write(process.argv[1].split("/").map(encodeURIComponent).join("/"))' "${remote_path}")"
page_url="${CHAPTER_SHAREPOINT_SITE%/}/root:/${encoded_path}:/children?\$select=name,size,file,@microsoft.graph.downloadUrl"

downloads_dir="${script_dir}/.downloads/${ref_id}"
mkdir -p "${downloads_dir}"
tmp_sums="$(mktemp "${downloads_dir}/.sums.XXXXXX")"
trap 'rm -f "${tmp_sums}"' EXIT

count=0
while [[ -n "${page_url}" ]]; do
  # The token is passed through a config file on a file descriptor, not on the command line.
  page_json="$(curl -sS --fail --proto '=https' --tlsv1.2 \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "${CHAPTER_SHAREPOINT_TOKEN}") \
    "${page_url}")" || fail "the SharePoint listing request failed for '${remote_path}'. Check the path and the token."

  rows="$(printf '%s' "${page_json}" | parse_page)" || fail "could not read the SharePoint listing for '${remote_path}'"

  page_url=""
  while IFS=$'\t' read -r kind value url; do
    case "${kind}" in
      FILE)
        # Download links are pre-authenticated, so the token is not sent to them.
        dest="${downloads_dir}/${value}"
        curl -sS --fail --proto '=https' --tlsv1.2 -o "${dest}" "${url}" \
          || fail "download failed for '${value}'"
        printf '%s  %s\n' "$(sha256_of "${dest}")" "${value}" >> "${tmp_sums}"
        count=$((count + 1))
        ;;
      NEXT)
        page_url="${value}"
        ;;
    esac
  done <<< "${rows}"
done

if [[ "${count}" -eq 0 ]]; then
  fail "no files found under '${remote_path}'"
fi

mv "${tmp_sums}" "${downloads_dir}/SHA256SUMS"
trap - EXIT
echo "fetch.sh: ${count} file(s) for ${ref_id} written to fixtures/reference/.downloads/${ref_id}/ (not committed)."

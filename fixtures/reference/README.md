# Reference intake packages

## Purpose

These files describe the structure of three past intake packages. They record which manifest
roles each package contained, which were missing, and what the intake guide says about them.
Station checks and manifest tests use them as a reference for what a real package looks like.

The three packages are identified only by these reference ids:

| Reference id   | Structure file      |
| -------------- | ------------------- |
| `ref-shawnee`  | `ref-shawnee.json`  |
| `ref-valley`   | `ref-valley.json`   |
| `ref-bay-road` | `ref-bay-road.json` |

The real project names and addresses are in Chapter's records only. They are not in this
repository, its history, its PRs or its Slack.

## Rules

- **Real files are never committed.** Not in git, not in a PR, not in `fixtures/`.
- The JSON files hold structure only: roles, statuses and notes. They hold no measurements,
  photographs, addresses, names or contact details.
- Role names are the closed set in `contract/schema/manifest.schema.json`.
- Each JSON file has these fields:
  - `present`: roles the package contained, with a `status` (`original`, `listed`, `limited` or
    `converted`) and a note.
  - `derived`: files that were derived outputs made later.
  - `missing`: gaps the intake guide documents.
  - `notDocumented`: roles the guide does not mention for that project. This does not mean the
    role was absent.
  - `outcome`: the guide's statement of what the records establish.

## Files

- `ref-*.json`: one structure file per past package.
- `fetch.sh`: pulls the real files from SharePoint into `.downloads/<reference-id>/`. It runs only
  when the credentials are set. It is not run by the test suite.
- `.gitignore`: ignores `.downloads/`.

## Fetching the real files

Only do this on a machine that is allowed to hold Chapter's project files.

```bash
CHAPTER_SHAREPOINT_SITE='<library base URL>' \
CHAPTER_SHAREPOINT_TOKEN='<your token>' \
  bash fixtures/reference/fetch.sh ref-shawnee '<folder path in the library>'
```

- Both variables are required. If either is missing, the script exits with a message and fetches
  nothing.
- The folder path is typed on the command line each time. It is not saved in this repository.
- The script prints no token. Do not paste the token into chats, prompts, Slack or commit
  messages.
- Downloaded files and a `SHA256SUMS` file go to `fixtures/reference/.downloads/<reference-id>/`.
  That folder is gitignored. Keep it out of any commit.

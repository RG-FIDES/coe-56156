---
name: publish-generated-site
description: 'Import or refresh a rendered static-site artifact from a source project frontend into this publishing repository. Use when initializing a new site repository, transferring generated site updates, or preparing a routine website release.'
argument-hint: 'Provide the source frontend directory or its generated site path'
---

# Publish Generated Site

This repository publishes one frontend of one source project. It stores the generated
artifact and the publishing harness — nothing else. Rendering happens in the source
project, where the private inputs live.

## Boundaries

- **Read-only source.** Never modify, render into, or clean up the source project.
- **Never publish** source files (`.qmd`, `.R`, `.Rmd`, notebooks, `.py`), data files
  (`.parquet`, `.sqlite`, `.db`, `.sav`, `.dta`), secrets (`.env`, keys), or caches
  (`.quarto`, `_freeze`, `_cache`, `data-private`). `scripts/sync-site.ps1` blocks these;
  a refusal is a signal to inspect the source, not to loosen the policy.
- **Never hand-edit generated files.** Report Quarto's trailing whitespace or formatting
  quirks rather than fixing them; parity with the source is the contract.
- **Never commit or push** unless the user explicitly asks.
- **Never change deployment configuration** as part of a content transfer.

## Which path applies

| Situation | Entry point |
| --- | --- |
| `site.config.json` has `"initialized": false` | `scripts/initialize-site.ps1` (`/import-frontend`) |
| Already initialized, new render to publish | `scripts/sync-site.ps1` (`/publish-site`) |
| Source project moved on this machine | Update `source.localPath` in `site.config.json` |
| Publishing a different frontend of the same project | Re-run `scripts/initialize-site.ps1` with the new `-FrontendPath` |

## Procedure

1. Resolve the supplied path. A frontend directory resolves to its generated site
   subdirectory (`_site` by default); a generated site path is used as-is.
2. Confirm the frontend was rendered after its latest content change. Stop and ask the
   user to re-render rather than publishing a stale artifact.
3. Check `git status --short` in this repository. Preserve pre-existing changes; stop if
   they make the transfer ambiguous.
4. Dry run:

   ```powershell
   ./scripts/sync-site.ps1
   ```

5. Report the added, changed, and deleted paths. Treat deletions as an explicit review
   point — never infer approval for them from a general update request.
6. Apply once the delta is understood:

   ```powershell
   ./scripts/sync-site.ps1 -Apply
   ```

   Add `-AllowDelete` only after deletions have been approved explicitly.
7. Verify: the script's post-transfer hash check passed, `git status --short` shows changes
   confined to the artifact directory, and `git diff --check` is clean.
8. When browser tools are available, serve the artifact locally and check the root entry
   point, the landing page, changed pages, navigation, and images in desktop and mobile
   viewports.
9. Summarize the transfer and hand off. The user reviews, commits, and pushes; the host
   redeploys on push to `main`.

## Configuration reference

`site.config.json` is the single source of truth for this harness.

| Key | Meaning |
| --- | --- |
| `source.localPath` | Absolute path to the source project on this machine (machine-specific) |
| `frontend.directory` | Frontend path relative to the source project root |
| `frontend.siteSubdirectory` | Generated output directory inside the frontend |
| `publish.artifactDirectory` | Directory in this repository holding the published bytes |
| `publish.entryPoint` | File served at the site root |
| `publish.landingPage` | Real first page, resolved through a meta-refresh stub when present |
| `publish.requiredFiles` | Files that must exist for a source to count as a complete site |
| `publish.forbiddenExtensions` / `forbiddenPathSegments` | Hard publication blocks |
| `publish.sensitiveTextPatterns` | Strings that raise a warning when found in generated assets |
| `publish.preservedPaths` | Repository-owned files inside the artifact directory that sync must not delete |

## Release boundary

The artifact directory is the authoritative published output for every configured host:
the primary static host (no build step), the optional GitHub Pages mirror in
`.github/workflows/deploy.yml`, and the optional Netlify configuration in `netlify.toml`.
Changing hosts is a deliberate, separate task.

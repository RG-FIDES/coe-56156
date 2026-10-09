---
name: publish-site
description: Refresh the published site artifact from the configured source project frontend.
disable-model-invocation: true
---
# Publish an updated site

Transfer a newly rendered site artifact from the configured source project frontend
into this repository.

Optional override: `${input:source:Leave empty to use the configured source, or give an explicit path to a rendered site directory}`

## Rules

- Never modify anything inside the source project.
- Never edit generated files by hand, including to fix whitespace or formatting.
  Byte-for-byte parity with the source is the contract.
- Treat every deletion as an explicit review point. A general "update the site" request
  is not approval to remove pages.
- Do not commit or push unless the user explicitly asks.

## Procedure

1. **Check preconditions.**
   - `site.config.json` has `"initialized": true`. If not, direct the user to `/import-frontend`.
   - `git status --short` in this repository is clean, or its pending changes are
     understood and unrelated to the artifact directory.

2. **Confirm the source is current.**
   Verify the configured source site directory exists and ask whether the frontend was
   re-rendered after the latest content changes. A stale render is the most common cause
   of a "nothing changed" transfer.

3. **Dry run.**

   ```powershell
   ./scripts/sync-site.ps1
   ```

   Use `-Source '<path>'` when the user supplied an override. Report the add, change,
   and delete counts and list the affected paths. Surface every warning verbatim.

4. **Interpret the delta.**
   Map the changed paths back to what the user said they changed. Flag anything
   unexpected — new top-level directories, wholesale asset churn, or pages disappearing —
   before applying.

5. **Apply.**

   ```powershell
   ./scripts/sync-site.ps1 -Apply
   ```

   Add `-AllowDelete` only after the user has approved the specific deletions.

6. **Verify.**
   - The script's post-transfer verification reported matching hashes.
   - `git status --short` shows changes only inside the artifact directory.
   - `git diff --check` reports no whitespace errors introduced outside generated files.

7. **Check the site renders.**
   When browser tools are available, serve the artifact directory locally and confirm the
   changed pages, navigation, and the root entry point in desktop and mobile viewports.

8. **Summarize.**
   State what changed, what was verified, and that the user should review and commit.
   Remind them that pushing to `main` triggers the deployment.

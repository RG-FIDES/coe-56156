# Copilot instructions

This is a **publishing repository** created from
[RG-FIDES/publish-site-template](https://github.com/RG-FIDES/publish-site-template).

It exists to make one frontend of one reproducible research project publicly available
as a static website. It contains the published bytes and the harness that moves them.
It does not contain analysis code, content sources, private data, or a build step.

## Architecture

```
source project (private inputs, code, content)
  └─ <frontend>/            render here
       └─ _site/            generated artifact
                │
                │  scripts/sync-site.ps1  (audited, hash-verified transfer)
                ▼
this repository
  └─ _site/                 committed artifact  ──push──▶  static host (no build)
```

`site.config.json` records the source project, the frontend, and the publish policy.
Read it before doing anything; it is the single source of truth for this harness.

## Non-negotiables

1. **The source project is read-only.** Never modify, render into, or clean it.
2. **Never hand-edit anything under the artifact directory.** It must match the source
   byte for byte. Defects are fixed in the source project and re-imported.
3. **Never publish** source files, data files, secrets, or caches. The transfer script
   blocks them. If it refuses, investigate the source — do not relax the policy.
4. **Deletions require explicit approval.** "Update the site" is not approval to remove
   pages.
5. **Never commit or push** unless the user explicitly asks.
6. **Never render here.** This repository has no build step by design; the private inputs
   required to render are not present.

## Entry points

| Task | Use |
| --- | --- |
| First-time setup against a frontend | `/import-frontend` → `scripts/initialize-site.ps1` |
| Publish an updated render | `/publish-site` → `scripts/sync-site.ps1` |
| Detailed procedure and policy reference | `.github/skills/publish-generated-site/SKILL.md` |

## Conventions

- Scripts are PowerShell 5.1-compatible, dry-run by default, and require `-Apply` to
  make changes. Preserve that shape in any new script.
- Shared script logic lives in `scripts/lib/` as dot-sourced function libraries with
  comment-based help. Scripts perform work; libraries only define functions.
- `templates/` holds files rendered at initialization with `{{TOKEN}}` placeholders.
  Adding a token means adding it to the `$tokens` map in `scripts/initialize-site.ps1`.
- New configuration keys must be added to `site.config.json` in the template, because
  PowerShell cannot assign properties that do not already exist on the parsed object.

# {{SITE_NAME}}

Public website repository for **{{SITE_TITLE}}**, generated from the
[{{SOURCE_REPO_NAME}}]({{SOURCE_REPO_URL}}) project.

This repository holds **only the generated site artifact** (`{{ARTIFACT_DIRECTORY}}/`)
plus the publishing harness. No analysis source, private data, or build caches are
stored here.

> Created from [RG-FIDES/publish-site-template](https://github.com/RG-FIDES/publish-site-template)
> and initialized on {{INITIALIZED_ON}} against `{{FRONTEND_DIRECTORY}}`.

## Publishing model

```
{{SOURCE_REPO_NAME}}                          {{SITE_NAME}}
--------------------------------              --------------------------------
{{FRONTEND_DIRECTORY}}/content/   --render-->
{{FRONTEND_DIRECTORY}}/{{ARTIFACT_DIRECTORY}}/     --import-->  {{ARTIFACT_DIRECTORY}}/  --push-->  main
                                                                                 |
                                                                    static host (no build step)
```

The source project owns the content, the code, and the data. This repository owns
only the published bytes. Rendering always happens in the source project, where the
private inputs live; nothing is rebuilt here.

- Entry point: `{{ARTIFACT_DIRECTORY}}/{{ENTRY_POINT}}`
- Landing page: `{{ARTIFACT_DIRECTORY}}/{{LANDING_PAGE}}`

## Updating the published site

1. Render the frontend in the source project.

   ```powershell
   cd {{SOURCE_REPO_NAME}}/{{FRONTEND_DIRECTORY}}
   quarto render
   ```

2. Open this repository in VS Code and run the `/publish-site` prompt, or run the
   transfer manually:

   ```powershell
   # Dry run: report what would change
   ./scripts/sync-site.ps1

   # Apply once the delta is understood
   ./scripts/sync-site.ps1 -Apply

   # Add -AllowDelete only when removals are intended
   ./scripts/sync-site.ps1 -Apply -AllowDelete
   ```

3. Review the diff, then commit and push to `main`. The host redeploys on push.

The transfer script refuses to publish source files, private data, or caches, and
verifies byte-for-byte parity with the source after applying.

## Configuration

`site.config.json` records the source project, the frontend, and the publish policy.
Update `source.localPath` when the source project lives elsewhere on a given machine;
everything else is machine-independent.

## Hosting

| Host          | Configuration                     | Status                       |
| ------------- | --------------------------------- | ---------------------------- |
| Static host   | Output directory `{{ARTIFACT_DIRECTORY}}`, no build command | Primary, configured in the host dashboard |
| GitHub Pages  | `.github/workflows/deploy.yml` mirrors `{{ARTIFACT_DIRECTORY}}/` to `gh-pages` | Enable in repository settings to use |
| Netlify       | `netlify.toml`                    | Optional, not connected by default |

`{{ARTIFACT_DIRECTORY}}/` is the authoritative artifact for all of them.

## License

See [LICENSE](LICENSE).

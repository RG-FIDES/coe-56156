<#
.SYNOPSIS
    Binds this template repository to a source project frontend and imports its
    generated site artifact for the first time.

.DESCRIPTION
    Run this once, immediately after creating a repository from
    `RG-FIDES/publish-site-template`. It:

      1. Resolves the frontend directory and its generated site output.
      2. Locates the source project's git repository root and origin URL.
      3. Audits the generated site against the publish policy.
      4. Detects the landing page (following a meta-refresh stub when present).
      5. Records everything in `site.config.json`.
      6. Renders `README.md` and `netlify.toml` from `templates/`.
      7. Imports the artifact by delegating to `scripts/sync-site.ps1`.

    The script is a dry run unless `-Apply` is supplied. Re-running with `-Apply`
    on an already-initialized repository is allowed and refreshes the recorded
    configuration; use `scripts/sync-site.ps1` for routine content updates.

.PARAMETER FrontendPath
    Path to the frontend directory in the source project (for example
    `C:\projects\absent-from-chronic\_frontend-1`) or directly to its generated
    site directory.

.PARAMETER SiteTitle
    Human-readable site title. Defaults to a title-cased form of the source
    repository name.

.PARAMETER SourceRepoUrl
    Public URL of the source project repository. Defaults to the `origin` remote
    of the source repository when git is available.

.PARAMETER ConfigPath
    Path to `site.config.json`. Defaults to the repository root.

.PARAMETER Apply
    Write configuration, render templates, and import the artifact.

.PARAMETER AllowDelete
    Passed through to the artifact transfer; permits removal of stale files.

.PARAMETER SkipImport
    Record configuration and render templates without transferring the artifact.

.EXAMPLE
    ./scripts/initialize-site.ps1 -FrontendPath 'C:\projects\absent-from-chronic\_frontend-1'
    Dry run: report what would be recorded and transferred.

.EXAMPLE
    ./scripts/initialize-site.ps1 -FrontendPath 'C:\projects\absent-from-chronic\_frontend-1' -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FrontendPath,

    [string]$SiteTitle,

    [string]$SourceRepoUrl,

    [string]$ConfigPath,

    [switch]$Apply,

    [switch]$AllowDelete,

    [switch]$SkipImport
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/site-config.ps1')
. (Join-Path $PSScriptRoot 'lib/site-artifact.ps1')

$repoRoot = Get-RepoRoot

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot 'site.config.json'
}
$config = Get-SiteConfig -Path $ConfigPath

# --- Resolve the frontend and its generated site ------------------------------

if (-not (Test-Path -LiteralPath $FrontendPath -PathType Container)) {
    throw "Frontend path does not exist: $FrontendPath"
}
$resolvedInput = (Resolve-Path -LiteralPath $FrontendPath).Path.TrimEnd('\', '/')

$siteSubdirectory = $config.frontend.siteSubdirectory
if ([string]::IsNullOrWhiteSpace($siteSubdirectory)) { $siteSubdirectory = '_site' }

if ((Split-Path -Leaf $resolvedInput) -eq $siteSubdirectory) {
    $sourceSiteRoot = $resolvedInput
    $frontendRoot = Split-Path -Parent $resolvedInput
}
else {
    $frontendRoot = $resolvedInput
    $sourceSiteRoot = Join-Path $frontendRoot $siteSubdirectory
}

if (-not (Test-Path -LiteralPath $sourceSiteRoot -PathType Container)) {
    throw "No generated site found at $sourceSiteRoot. Render the frontend in the source project first (for example, run 'quarto render' in $frontendRoot)."
}
$sourceSiteRoot = (Resolve-Path -LiteralPath $sourceSiteRoot).Path.TrimEnd('\', '/')

# --- Identify the source project ----------------------------------------------

$sourceRepoRoot = Find-GitRepositoryRoot -StartPath $frontendRoot
if (-not $sourceRepoRoot) {
    # Fall back to the frontend's parent when the source is not a git working tree.
    $sourceRepoRoot = Split-Path -Parent $frontendRoot
    Write-Warning "Could not find a git repository above $frontendRoot. Using $sourceRepoRoot as the source project root."
}
$sourceRepoRoot = $sourceRepoRoot.TrimEnd('\', '/')

$sourceRepoName = Split-Path -Leaf $sourceRepoRoot
$frontendDirectory = $frontendRoot.Substring($sourceRepoRoot.Length).Trim('\', '/').Replace('\', '/')

if ([string]::IsNullOrWhiteSpace($SourceRepoUrl)) {
    $SourceRepoUrl = Get-GitRemoteUrl -RepositoryPath $sourceRepoRoot
}

$siteName = Split-Path -Leaf $repoRoot

if ([string]::IsNullOrWhiteSpace($SiteTitle)) {
    $SiteTitle = (($sourceRepoName -replace '[-_]', ' ') -split '\s+' |
        Where-Object { $_ } |
        ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ' '
}

# --- Audit the generated site --------------------------------------------------

$audit = Test-PublishableSite -Root $sourceSiteRoot -PublishPolicy $config.publish

# sync-site.ps1 re-runs this audit and reports the warnings, so only surface them here
# when the transfer will not run.
if ($SkipImport) {
    foreach ($warning in $audit.Warnings) {
        Write-Warning $warning
    }
}

if ($audit.Problems.Count -gt 0) {
    $detail = ($audit.Problems | Select-Object -First 25) -join [Environment]::NewLine
    throw "The generated site is not publishable:$([Environment]::NewLine)$detail"
}

# --- Detect the landing page ---------------------------------------------------

$entryPoint = $config.publish.entryPoint
if ([string]::IsNullOrWhiteSpace($entryPoint)) { $entryPoint = 'index.html' }

$landingPage = Get-MetaRefreshTarget -Path (Join-Path $sourceSiteRoot $entryPoint)
if ([string]::IsNullOrWhiteSpace($landingPage)) { $landingPage = $entryPoint }

$artifactDirectory = $config.publish.artifactDirectory
if ([string]::IsNullOrWhiteSpace($artifactDirectory)) { $artifactDirectory = '_site' }

$fileCount = (Get-ChildItem -LiteralPath $sourceSiteRoot -Recurse -File -Force | Measure-Object).Count

# --- Report the plan -----------------------------------------------------------

Write-Output '--- Initialization plan ---'
Write-Output "Site repository:   $siteName ($repoRoot)"
Write-Output "Site title:        $SiteTitle"
Write-Output "Source project:    $sourceRepoName ($sourceRepoRoot)"
Write-Output "Source repo URL:   $(if ($SourceRepoUrl) { $SourceRepoUrl } else { '(unknown)' })"
Write-Output "Frontend:          $frontendDirectory"
Write-Output "Generated site:    $sourceSiteRoot ($fileCount files)"
Write-Output "Entry point:       $entryPoint"
Write-Output "Landing page:      $landingPage"
Write-Output "Artifact target:   $artifactDirectory"
Write-Output ''

if (-not $Apply) {
    Write-Output 'Dry run only. Re-run with -Apply to record configuration and import the artifact.'
    Write-Output ''
    Write-Output '--- Artifact transfer preview ---'
    & (Join-Path $PSScriptRoot 'sync-site.ps1') -Source $sourceSiteRoot -ConfigPath $ConfigPath
    return
}

# --- Record configuration ------------------------------------------------------

$config.siteName = $siteName
$config.siteTitle = $SiteTitle
$config.source.repoName = $sourceRepoName
$config.source.repoUrl = if ($SourceRepoUrl) { $SourceRepoUrl } else { '' }
$config.source.localPath = $sourceRepoRoot
$config.frontend.directory = $frontendDirectory
$config.frontend.siteSubdirectory = $siteSubdirectory
$config.publish.entryPoint = $entryPoint
$config.publish.landingPage = $landingPage
$config.publish.artifactDirectory = $artifactDirectory
$config.initialized = $true
$config.initializedOn = (Get-Date).ToString('yyyy-MM-dd')

Save-SiteConfig -Config $config -Path $ConfigPath
Write-Output "Recorded configuration in $ConfigPath"

# --- Render templates ----------------------------------------------------------

$tokens = @{
    '{{SITE_NAME}}'          = $siteName
    '{{SITE_TITLE}}'         = $SiteTitle
    '{{SOURCE_REPO_NAME}}'   = $sourceRepoName
    '{{SOURCE_REPO_URL}}'    = if ($SourceRepoUrl) { $SourceRepoUrl } else { "https://github.com/RG-FIDES/$sourceRepoName" }
    '{{FRONTEND_DIRECTORY}}' = $frontendDirectory
    '{{ARTIFACT_DIRECTORY}}' = $artifactDirectory
    '{{ENTRY_POINT}}'        = $entryPoint
    '{{LANDING_PAGE}}'       = $landingPage
    '{{INITIALIZED_ON}}'     = $config.initializedOn
}

$renderMap = @{
    'README.site.md' = 'README.md'
    'netlify.toml'   = 'netlify.toml'
}

foreach ($templateName in $renderMap.Keys) {
    $templatePath = Join-Path $repoRoot "templates/$templateName"
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        Write-Warning "Template not found, skipping: $templatePath"
        continue
    }

    $content = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
    foreach ($token in $tokens.Keys) {
        $content = $content.Replace($token, $tokens[$token])
    }

    $outputPath = Join-Path $repoRoot $renderMap[$templateName]
    Set-Content -LiteralPath $outputPath -Value $content -Encoding UTF8
    Write-Output "Rendered $($renderMap[$templateName])"
}

# --- Import the artifact -------------------------------------------------------

if ($SkipImport) {
    Write-Output ''
    Write-Output 'Skipped artifact import (-SkipImport). Run scripts/sync-site.ps1 -Apply when ready.'
    return
}

Write-Output ''
Write-Output '--- Artifact transfer ---'
& (Join-Path $PSScriptRoot 'sync-site.ps1') -Source $sourceSiteRoot -ConfigPath $ConfigPath -Apply:$true -AllowDelete:$AllowDelete

Write-Output ''
Write-Output 'Initialization complete. Review the diff, then commit and push to publish.'

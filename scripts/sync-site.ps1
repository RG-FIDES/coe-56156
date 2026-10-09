<#
.SYNOPSIS
    Synchronizes a generated static-site artifact from a source project frontend
    into this publishing repository.

.DESCRIPTION
    This repository stores only the generated site artifact. `sync-site.ps1`
    transfers that artifact from the source project's rendered output directory
    (for example `<project>/_frontend-1/_site`) into this repository's artifact
    directory (`_site` by default).

    The script is a dry run unless `-Apply` is supplied, and it refuses to delete
    files unless `-AllowDelete` is also supplied. Before transferring anything it
    audits the source against the publish policy in `site.config.json` so that
    source code, private data, and caches can never reach the public repository.

    After applying, the script re-inventories both trees and fails if any file
    differs, guaranteeing byte-for-byte parity with the source.

.PARAMETER Source
    Absolute or relative path to the generated site directory to publish. When
    omitted, the path is derived from `site.config.json`. A path pointing at the
    frontend directory itself is resolved to its site subdirectory.

.PARAMETER Destination
    Artifact directory in this repository. Defaults to the configured
    `publish.artifactDirectory`.

.PARAMETER ConfigPath
    Path to `site.config.json`. Defaults to the repository root.

.PARAMETER Apply
    Perform the transfer. Without this switch the script only reports the delta.

.PARAMETER AllowDelete
    Permit removal of destination files that no longer exist in the source.

.EXAMPLE
    ./scripts/sync-site.ps1
    Dry run against the configured source.

.EXAMPLE
    ./scripts/sync-site.ps1 -Source 'C:\projects\absent-from-chronic\_frontend-1\_site' -Apply

.EXAMPLE
    ./scripts/sync-site.ps1 -Apply -AllowDelete
    Apply a transfer that removes retired pages.
#>
[CmdletBinding()]
param(
    [string]$Source,

    [string]$Destination,

    [string]$ConfigPath,

    [switch]$Apply,

    [switch]$AllowDelete
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/site-config.ps1')
. (Join-Path $PSScriptRoot 'lib/site-artifact.ps1')

$repoRoot = Get-RepoRoot

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot 'site.config.json'
}
$config = Get-SiteConfig -Path $ConfigPath

# --- Resolve source -----------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Source)) {
    $sourceRoot = Resolve-SourceSitePath -Config $config
}
else {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source directory does not exist: $Source"
    }

    $sourceRoot = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\', '/')

    # Accept a frontend directory and descend into its generated site.
    $siteSubdirectory = $config.frontend.siteSubdirectory
    if ([string]::IsNullOrWhiteSpace($siteSubdirectory)) { $siteSubdirectory = '_site' }

    $nested = Join-Path $sourceRoot $siteSubdirectory
    if ((Split-Path -Leaf $sourceRoot) -ne $siteSubdirectory -and (Test-Path -LiteralPath $nested -PathType Container)) {
        $sourceRoot = (Resolve-Path -LiteralPath $nested).Path.TrimEnd('\', '/')
    }
}

# --- Resolve destination ------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $artifactDirectory = $config.publish.artifactDirectory
    if ([string]::IsNullOrWhiteSpace($artifactDirectory)) { $artifactDirectory = '_site' }
    $Destination = Join-Path $repoRoot $artifactDirectory
}

if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    if (-not $Apply) {
        throw "Destination directory does not exist: $Destination. Create it, or run scripts/initialize-site.ps1 first."
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}
$destinationRoot = (Resolve-Path -LiteralPath $Destination).Path.TrimEnd('\', '/')

if ($sourceRoot -eq $destinationRoot) {
    throw 'Source and destination must be different directories.'
}

# --- Audit the source against the publish policy ------------------------------

$audit = Test-PublishableSite -Root $sourceRoot -PublishPolicy $config.publish

foreach ($warning in $audit.Warnings) {
    Write-Warning $warning
}

if ($audit.Problems.Count -gt 0) {
    $detail = ($audit.Problems | Select-Object -First 25) -join [Environment]::NewLine
    throw "The source directory is not publishable:$([Environment]::NewLine)$detail"
}

# --- Compare ------------------------------------------------------------------

$sourceFiles = Get-SiteInventory -Root $sourceRoot
$destinationFiles = Get-SiteInventory -Root $destinationRoot

# Repository-owned placeholders live inside the artifact directory but are not
# part of the generated site; they must never be reported as deletions.
foreach ($preserved in @($config.publish.preservedPaths)) {
    if (-not [string]::IsNullOrWhiteSpace($preserved)) {
        $destinationFiles.Remove($preserved)
    }
}

$delta = Get-SiteDelta -SourceInventory $sourceFiles -DestinationInventory $destinationFiles

Write-Output "Source:      $sourceRoot"
Write-Output "Destination: $destinationRoot"
Write-Output "Added:       $($delta.Added.Count)"
Write-Output "Changed:     $($delta.Changed.Count)"
Write-Output "Deleted:     $($delta.Deleted.Count)"
Write-Output ''

foreach ($relativePath in $delta.Added) { Write-Output "ADD    $relativePath" }
foreach ($relativePath in $delta.Changed) { Write-Output "CHANGE $relativePath" }
foreach ($relativePath in $delta.Deleted) { Write-Output "DELETE $relativePath" }

if (-not $Apply) {
    Write-Output ''
    Write-Output 'Dry run only. Re-run with -Apply to synchronize.'
    return
}

if ($delta.Deleted.Count -gt 0 -and -not $AllowDelete) {
    throw "The transfer would delete $($delta.Deleted.Count) file(s). Review the dry run and re-run with -AllowDelete if the removals are intended."
}

# --- Apply --------------------------------------------------------------------

foreach ($relativePath in @($delta.Added) + @($delta.Changed)) {
    $destinationPath = Join-Path $destinationRoot $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $sourceFiles[$relativePath].FullName -Destination $destinationPath -Force
}

foreach ($relativePath in $delta.Deleted) {
    Remove-Item -LiteralPath (Join-Path $destinationRoot $relativePath) -Force
}

# Remove directories left empty by deletions.
if ($delta.Deleted.Count -gt 0) {
    Get-ChildItem -LiteralPath $destinationRoot -Recurse -Directory -Force |
        Sort-Object -Property FullName -Descending |
        Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}

# --- Verify -------------------------------------------------------------------

$verifySource = Get-SiteInventory -Root $sourceRoot
$verifyDestination = Get-SiteInventory -Root $destinationRoot

foreach ($preserved in @($config.publish.preservedPaths)) {
    if (-not [string]::IsNullOrWhiteSpace($preserved)) {
        $verifyDestination.Remove($preserved)
    }
}

$verifyDelta = Get-SiteDelta -SourceInventory $verifySource -DestinationInventory $verifyDestination

if ($verifyDelta.Added.Count -ne 0 -or $verifyDelta.Changed.Count -ne 0 -or $verifyDelta.Deleted.Count -ne 0) {
    throw "Post-transfer verification failed: $($verifyDelta.Added.Count) added, $($verifyDelta.Changed.Count) changed, $($verifyDelta.Deleted.Count) deleted still differ."
}

Write-Output ''
Write-Output 'Transfer complete. Source and destination hashes match.'
Write-Output 'Review the diff, then commit and push when the result is correct.'

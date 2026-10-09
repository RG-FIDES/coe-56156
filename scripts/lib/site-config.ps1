# site-config.ps1 -------------------------------------------------------------
# Shared helpers for reading, validating, and resolving `site.config.json`.
# Dot-source this file; it defines functions only and performs no side effects.
# -----------------------------------------------------------------------------

function Get-RepoRoot {
    <#
    .SYNOPSIS
        Returns the root of this site repository (the parent of `scripts/`).
    #>
    [CmdletBinding()]
    param(
        # Defaults to `scripts/`, the parent of the directory holding this file.
        [string]$ScriptsDirectory = (Split-Path -Parent $PSScriptRoot)
    )

    return (Resolve-Path -LiteralPath (Split-Path -Parent $ScriptsDirectory)).Path
}

function Get-SiteConfig {
    <#
    .SYNOPSIS
        Loads `site.config.json` and returns it as an object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        throw "Configuration file is not valid JSON ($Path): $($_.Exception.Message)"
    }
}

function Save-SiteConfig {
    <#
    .SYNOPSIS
        Writes a configuration object back to disk as formatted JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $json = $Config | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Test-SiteConfigInitialized {
    <#
    .SYNOPSIS
        Returns $true when the template has been bound to a source frontend.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Config
    )

    return [bool]$Config.initialized
}

function Resolve-SourceSitePath {
    <#
    .SYNOPSIS
        Derives the absolute path of the source frontend's generated site directory.
    .DESCRIPTION
        Combines `source.localPath`, `frontend.directory`, and `frontend.siteSubdirectory`
        from the configuration. Throws a directive error when the template has not been
        initialized yet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Config
    )

    if (-not (Test-SiteConfigInitialized -Config $Config)) {
        throw "This repository has not been initialized yet. Run the /import-frontend prompt, or invoke scripts/initialize-site.ps1 with -FrontendPath."
    }

    $localPath = $Config.source.localPath
    if ([string]::IsNullOrWhiteSpace($localPath)) {
        throw "site.config.json does not record source.localPath. Re-run scripts/initialize-site.ps1, or pass -Source explicitly."
    }

    $frontendDirectory = $Config.frontend.directory
    $siteSubdirectory = $Config.frontend.siteSubdirectory

    $candidate = Join-Path -Path $localPath -ChildPath $frontendDirectory
    $candidate = Join-Path -Path $candidate -ChildPath $siteSubdirectory

    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "Configured source site directory does not exist on this machine: $candidate. Update source.localPath in site.config.json, or pass -Source explicitly."
    }

    return (Resolve-Path -LiteralPath $candidate).Path.TrimEnd('\', '/')
}

function Get-GitRemoteUrl {
    <#
    .SYNOPSIS
        Returns the `origin` remote URL of a repository, or $null when unavailable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return $null
    }

    $url = & git -C $RepositoryPath remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($url)) {
        return $null
    }

    $url = $url.Trim()

    # Normalize SSH form (git@github.com:Org/repo.git) into an https URL.
    if ($url -match '^git@([^:]+):(.+?)(\.git)?$') {
        $url = "https://$($Matches[1])/$($Matches[2])"
    }
    elseif ($url -match '^(https?://.+?)(\.git)$') {
        $url = $Matches[1]
    }

    return $url
}

function Find-GitRepositoryRoot {
    <#
    .SYNOPSIS
        Walks upward from a path until a directory containing `.git` is found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StartPath
    )

    $current = (Resolve-Path -LiteralPath $StartPath).Path
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath (Join-Path $current '.git')) {
            return $current
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }

    return $null
}

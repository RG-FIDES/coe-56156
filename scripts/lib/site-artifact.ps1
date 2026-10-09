# site-artifact.ps1 -----------------------------------------------------------
# Shared helpers for inspecting a generated static-site directory: inventories,
# publishability checks, and landing-page discovery.
# Dot-source this file; it defines functions only and performs no side effects.
# -----------------------------------------------------------------------------

function Get-SiteInventory {
    <#
    .SYNOPSIS
        Builds a hashtable of relative path -> file metadata (SHA256 hash and size).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $inventory = @{}
    $normalizedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')

    Get-ChildItem -LiteralPath $normalizedRoot -Recurse -File -Force | ForEach-Object {
        $relativePath = $_.FullName.Substring($normalizedRoot.Length + 1).Replace('\', '/')
        $inventory[$relativePath] = [pscustomobject]@{
            FullName = $_.FullName
            Hash     = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            Length   = $_.Length
        }
    }

    return $inventory
}

function Test-PublishableSite {
    <#
    .SYNOPSIS
        Audits a generated site directory against the repository's publish policy.
    .DESCRIPTION
        Returns an object with `Problems` (blocking) and `Warnings` (advisory).
        Blocking problems are missing required files, forbidden file extensions,
        and forbidden path segments. Warnings are textual matches of sensitive
        patterns inside generated assets.
    .OUTPUTS
        PSCustomObject with Problems and Warnings string arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        $PublishPolicy
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    $normalizedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')

    foreach ($required in @($PublishPolicy.requiredFiles)) {
        if ([string]::IsNullOrWhiteSpace($required)) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $normalizedRoot $required) -PathType Leaf)) {
            $problems.Add("Missing required file: $required")
        }
    }

    $forbiddenExtensions = @($PublishPolicy.forbiddenExtensions)
    $forbiddenSegments   = @($PublishPolicy.forbiddenPathSegments)

    foreach ($file in Get-ChildItem -LiteralPath $normalizedRoot -Recurse -File -Force) {
        $relativePath = $file.FullName.Substring($normalizedRoot.Length + 1).Replace('\', '/')

        if ($forbiddenExtensions -contains $file.Extension) {
            $problems.Add("Forbidden file type ($($file.Extension)): $relativePath")
            continue
        }

        $segments = $relativePath -split '/'
        foreach ($segment in $forbiddenSegments) {
            if ($segments -contains $segment) {
                $problems.Add("Forbidden path segment ('$segment'): $relativePath")
                break
            }
        }
    }

    foreach ($pattern in @($PublishPolicy.sensitiveTextPatterns)) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }

        $textHits = Get-ChildItem -LiteralPath $normalizedRoot -Recurse -File -Include *.html, *.htm, *.json, *.css, *.js -ErrorAction SilentlyContinue |
            Select-String -SimpleMatch $pattern -ErrorAction SilentlyContinue |
            Select-Object -First 10

        foreach ($hit in $textHits) {
            $relativePath = $hit.Path.Substring($normalizedRoot.Length + 1).Replace('\', '/')
            $warnings.Add("Sensitive pattern '$pattern' found in ${relativePath}:$($hit.LineNumber)")
        }
    }

    return [pscustomobject]@{
        Problems = $problems.ToArray()
        Warnings = $warnings.ToArray()
    }
}

function Get-MetaRefreshTarget {
    <#
    .SYNOPSIS
        Extracts the redirect target from an HTML meta-refresh stub.
    .DESCRIPTION
        Quarto and similar generators write a root `index.html` that immediately
        redirects into a nested landing page. Knowing that target lets the
        publishing harness configure host-level rewrites and verify the site root.
    .OUTPUTS
        The relative redirect target, or $null when the file is not a stub.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $html = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

    # The URL is frequently nested-quoted, e.g. content="0;URL='content/index.html'".
    $pattern = '(?is)<meta[^>]*http-equiv\s*=\s*["'']refresh["''][^>]*content\s*=\s*["''][^"'']*url\s*=\s*[''"]?([^"''\s;>]+)'
    $match = [regex]::Match($html, $pattern)

    if ($match.Success) {
        return $match.Groups[1].Value.Trim().TrimStart('.', '/')
    }

    return $null
}

function Get-SiteDelta {
    <#
    .SYNOPSIS
        Compares two inventories and returns the add/change/delete sets.
    .OUTPUTS
        PSCustomObject with Added, Changed, and Deleted relative-path arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SourceInventory,

        [Parameter(Mandatory)]
        [hashtable]$DestinationInventory
    )

    $added = @($SourceInventory.Keys | Where-Object { -not $DestinationInventory.ContainsKey($_) } | Sort-Object)
    $changed = @($SourceInventory.Keys | Where-Object {
            $DestinationInventory.ContainsKey($_) -and $SourceInventory[$_].Hash -ne $DestinationInventory[$_].Hash
        } | Sort-Object)
    $deleted = @($DestinationInventory.Keys | Where-Object { -not $SourceInventory.ContainsKey($_) } | Sort-Object)

    return [pscustomobject]@{
        Added   = $added
        Changed = $changed
        Deleted = $deleted
    }
}

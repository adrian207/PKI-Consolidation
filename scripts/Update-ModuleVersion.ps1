<#
.SYNOPSIS
    Updates module version with semantic versioning

.DESCRIPTION
    Automates version bumping across manifest, module file, and changelog
    following semantic versioning (MAJOR.MINOR.PATCH)

.PARAMETER VersionType
    Type of version bump: Major, Minor, or Patch

.PARAMETER NewVersion
    Specify exact version (e.g., '1.4.0')

.PARAMETER WhatIf
    Preview changes without applying

.EXAMPLE
    .\Update-ModuleVersion.ps1 -VersionType Minor

.EXAMPLE
    .\Update-ModuleVersion.ps1 -NewVersion '2.0.0'

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Bump')]
param(
    [Parameter(Mandatory, ParameterSetName='Bump')]
    [ValidateSet('Major', 'Minor', 'Patch')]
    [string]$VersionType,
    
    [Parameter(Mandatory, ParameterSetName='Exact')]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$NewVersion
)

$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PSScriptRoot '..\PKI-Consolidation.psd1'
$modulePath = Join-Path $PSScriptRoot '..\PKI-Consolidation.psm1'
$changelogPath = Join-Path $PSScriptRoot '..\CHANGELOG.md'

# Read current version
Write-Host "Reading current version..." -ForegroundColor Cyan
$manifest = Import-PowerShellDataFile $manifestPath
$currentVersion = [version]$manifest.ModuleVersion

Write-Host "Current Version: $currentVersion" -ForegroundColor Yellow

# Calculate new version
if ($PSCmdlet.ParameterSetName -eq 'Bump') {
    $newVer = switch ($VersionType) {
        'Major' { [version]::new($currentVersion.Major + 1, 0, 0) }
        'Minor' { [version]::new($currentVersion.Major, $currentVersion.Minor + 1, 0) }
        'Patch' { [version]::new($currentVersion.Major, $currentVersion.Minor, $currentVersion.Build + 1) }
    }
    $NewVersion = $newVer.ToString()
}

Write-Host "New Version: $NewVersion" -ForegroundColor Green

if ($currentVersion.ToString() -eq $NewVersion) {
    Write-Warning "Version is already $NewVersion"
    return
}

# Update manifest
if ($PSCmdlet.ShouldProcess($manifestPath, "Update version to $NewVersion")) {
    Write-Host "`nUpdating module manifest..." -ForegroundColor Cyan
    $manifestContent = Get-Content $manifestPath -Raw
    $manifestContent = $manifestContent -replace "ModuleVersion = '[\d\.]+'", "ModuleVersion = '$NewVersion'"
    $manifestContent | Set-Content $manifestPath -NoNewline
    Write-Host "✓ Manifest updated" -ForegroundColor Green
}

# Update module file
if ($PSCmdlet.ShouldProcess($modulePath, "Update version to $NewVersion")) {
    Write-Host "Updating module file..." -ForegroundColor Cyan
    $moduleContent = Get-Content $modulePath -Raw
    $moduleContent = $moduleContent -replace "\`$script:ModuleVersion = '[\d\.]+'", "`$script:ModuleVersion = '$NewVersion'"
    $moduleContent | Set-Content $modulePath -NoNewline
    Write-Host "✓ Module file updated" -ForegroundColor Green
}

# Update changelog
if ($PSCmdlet.ShouldProcess($changelogPath, "Add version $NewVersion entry")) {
    Write-Host "Updating changelog..." -ForegroundColor Cyan
    $changelogContent = Get-Content $changelogPath -Raw
    
    $date = Get-Date -Format 'yyyy-MM-dd'
    $newEntry = @"
## [$NewVersion] - $date

### Added
- 

### Changed
- 

### Fixed
- 

---

"@
    
    # Insert after [Unreleased] section
    $changelogContent = $changelogContent -replace '(## \[Unreleased\].*?---\s*)', "`$1`n$newEntry"
    $changelogContent | Set-Content $changelogPath -NoNewline
    Write-Host "✓ Changelog updated (please fill in details)" -ForegroundColor Green
}

# Git operations
if ($PSCmdlet.ShouldProcess("Git", "Create version commit and tag")) {
    Write-Host "`nGit Operations:" -ForegroundColor Cyan
    
    $gitStatus = git status --porcelain
    if ($gitStatus) {
        Write-Host "Staging changes..." -ForegroundColor Yellow
        git add $manifestPath $modulePath $changelogPath
        
        Write-Host "Creating commit..." -ForegroundColor Yellow
        git commit -m "chore: Bump version to $NewVersion"
        
        Write-Host "Creating tag..." -ForegroundColor Yellow
        git tag -a "v$NewVersion" -m "Release v$NewVersion"
        
        Write-Host "✓ Git commit and tag created" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Review changes: git show" -ForegroundColor White
        Write-Host "  2. Push changes: git push origin main" -ForegroundColor White
        Write-Host "  3. Push tag: git push origin v$NewVersion" -ForegroundColor White
        Write-Host "  4. Create GitHub release from tag" -ForegroundColor White
    }
}

Write-Host "`n✓ Version updated successfully!" -ForegroundColor Green
Write-Host "Old Version: $currentVersion" -ForegroundColor Gray
Write-Host "New Version: $NewVersion" -ForegroundColor Green


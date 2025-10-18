<#
.SYNOPSIS
    Comprehensive test runner for PKI-Consolidation project

.DESCRIPTION
    Runs all Pester tests and generates coverage reports for the PKI-Consolidation tool

.PARAMETER TestPath
    Path to the tests directory (default: script location)

.PARAMETER OutputFormat
    Output format for test results (NUnitXml, JUnitXml, or Console)

.PARAMETER CodeCoverage
    Enable code coverage analysis

.EXAMPLE
    .\Invoke-AllTests.ps1

.EXAMPLE
    .\Invoke-AllTests.ps1 -OutputFormat NUnitXml -CodeCoverage

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Requires: Pester 5.0+
#>

[CmdletBinding()]
param(
    [string]$TestPath = $PSScriptRoot,
    
    [ValidateSet('Console', 'NUnitXml', 'JUnitXml')]
    [string]$OutputFormat = 'Console',
    
    [switch]$CodeCoverage,
    
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\test-results')
)

#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Banner
Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║          PKI-Consolidation Test Suite                       ║
║          Author: Adrian Johnson <adrian207@gmail.com>        ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Check Pester version
$pesterModule = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

if (-not $pesterModule -or $pesterModule.Version.Major -lt 5) {
    Write-Warning "Pester 5.0+ is required. Installing..."
    try {
        Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
        Import-Module Pester -MinimumVersion 5.0.0 -Force
    }
    catch {
        Write-Error "Failed to install Pester: $_"
        exit 1
    }
}

Write-Host "[Test Runner] Using Pester v$($pesterModule.Version)" -ForegroundColor Green

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Configure Pester
$pesterConfig = New-PesterConfiguration

# Test discovery
$pesterConfig.Run.Path = $TestPath
$pesterConfig.Run.PassThru = $true

# Output configuration
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

switch ($OutputFormat) {
    'NUnitXml' {
        $outputFile = Join-Path $OutputPath "test-results-$timestamp.xml"
        $pesterConfig.TestResult.Enabled = $true
        $pesterConfig.TestResult.OutputFormat = 'NUnitXml'
        $pesterConfig.TestResult.OutputPath = $outputFile
        Write-Host "[Test Runner] Results will be saved to: $outputFile" -ForegroundColor Cyan
    }
    'JUnitXml' {
        $outputFile = Join-Path $OutputPath "test-results-$timestamp.xml"
        $pesterConfig.TestResult.Enabled = $true
        $pesterConfig.TestResult.OutputFormat = 'JUnitXml'
        $pesterConfig.TestResult.OutputPath = $outputFile
        Write-Host "[Test Runner] Results will be saved to: $outputFile" -ForegroundColor Cyan
    }
    'Console' {
        $pesterConfig.Output.Verbosity = 'Detailed'
    }
}

# Code coverage
if ($CodeCoverage) {
    $modulePath = Join-Path $PSScriptRoot '..\modules'
    $coverageFiles = @(
        (Join-Path $modulePath 'PKI-Security.psm1'),
        (Join-Path $modulePath 'PKI-Performance.psm1'),
        (Join-Path $modulePath 'PKI-OCSP.psm1')
    ) | Where-Object { Test-Path $_ }
    
    if ($coverageFiles) {
        $pesterConfig.CodeCoverage.Enabled = $true
        $pesterConfig.CodeCoverage.Path = $coverageFiles
        $pesterConfig.CodeCoverage.OutputFormat = 'JaCoCo'
        $pesterConfig.CodeCoverage.OutputPath = Join-Path $OutputPath "coverage-$timestamp.xml"
        Write-Host "[Test Runner] Code coverage enabled for $($coverageFiles.Count) modules" -ForegroundColor Cyan
    }
    else {
        Write-Warning "No module files found for code coverage"
    }
}

# Run tests
Write-Host "`n[Test Runner] Discovering and running tests..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Gray

try {
    $results = Invoke-Pester -Configuration $pesterConfig
    
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "`n📊 Test Summary" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    
    Write-Host "Total Tests:    " -NoNewline
    Write-Host $results.TotalCount -ForegroundColor White
    
    Write-Host "Passed:         " -NoNewline
    Write-Host $results.PassedCount -ForegroundColor Green
    
    Write-Host "Failed:         " -NoNewline
    Write-Host $results.FailedCount -ForegroundColor $(if ($results.FailedCount -eq 0) { 'Green' } else { 'Red' })
    
    Write-Host "Skipped:        " -NoNewline
    Write-Host $results.SkippedCount -ForegroundColor Yellow
    
    Write-Host "Duration:       " -NoNewline
    Write-Host "$([math]::Round($results.Duration.TotalSeconds, 2))s" -ForegroundColor White
    
    # Code coverage summary
    if ($CodeCoverage -and $results.CodeCoverage) {
        Write-Host "`n📈 Code Coverage" -ForegroundColor Cyan
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        
        $coverage = $results.CodeCoverage
        $coveragePercent = if ($coverage.NumberOfCommandsAnalyzed -gt 0) {
            [math]::Round(($coverage.NumberOfCommandsExecuted / $coverage.NumberOfCommandsAnalyzed) * 100, 2)
        } else { 0 }
        
        Write-Host "Commands Analyzed:  $($coverage.NumberOfCommandsAnalyzed)"
        Write-Host "Commands Executed:  $($coverage.NumberOfCommandsExecuted)"
        Write-Host "Commands Missed:    $($coverage.NumberOfCommandsMissed)"
        Write-Host "Coverage:           " -NoNewline
        
        $coverageColor = if ($coveragePercent -ge 80) { 'Green' } elseif ($coveragePercent -ge 60) { 'Yellow' } else { 'Red' }
        Write-Host "$coveragePercent%" -ForegroundColor $coverageColor
    }
    
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Gray
    
    # Exit code based on test results
    if ($results.FailedCount -gt 0) {
        Write-Host "❌ Tests failed!" -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "✅ All tests passed!" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Error "Test execution failed: $_"
    exit 1
}


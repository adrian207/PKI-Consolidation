<#
.SYNOPSIS
    PKI-Consolidation PowerShell Module

.DESCRIPTION
    Enterprise PKI Consolidation Tool for Active Directory Certificate Services (AD CS).
    
    This module provides a complete end-to-end workflow for consolidating PKI hierarchies
    during mergers, acquisitions, or infrastructure modernization projects.

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Version: 1.3.0
    Requires: PowerShell 5.1+
    License: MIT
    
.LINK
    https://github.com/adrian207/PKI-Consolidation
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest

# Module variables
$script:ModuleRoot = $PSScriptRoot
$script:ModuleVersion = '1.3.0'

#region Module Initialization

Write-Verbose "Loading PKI-Consolidation Module v$script:ModuleVersion"

# Import nested modules (they're declared in the manifest)
# PKI-Security.psm1, PKI-Performance.psm1, PKI-OCSP.psm1

# Set default configuration
$script:DefaultOutDir = 'C:\PKI\Consolidation'
$script:DefaultConfigPath = Join-Path $script:DefaultOutDir 'config\pki-consolidation.json'

#endregion

#region Public Functions

<#
.SYNOPSIS
    Starts the interactive PKI Consolidation tool

.DESCRIPTION
    Launches the menu-driven PKI consolidation interface with all 9 phases

.PARAMETER OutDir
    Output directory for reports, exports, and working files

.PARAMETER DryRun
    Preview mode - no actual changes will be made

.PARAMETER GuardedMode
    Stage registry changes for review before applying

.EXAMPLE
    Start-PKIConsolidation

.EXAMPLE
    Start-PKIConsolidation -OutDir 'D:\PKI' -DryRun

.EXAMPLE
    Start-PKIConsolidation -GuardedMode $false
#>
function Start-PKIConsolidation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutDir = $script:DefaultOutDir,
        
        [Parameter()]
        [switch]$DryRun,
        
        [Parameter()]
        [bool]$GuardedMode = $true,
        
        [Parameter()]
        [string]$VaultName,
        
        [Parameter()]
        [string]$KeyfactorBaseUrl
    )
    
    # Set global variables for the enhanced script
    $Global:OutDir = $OutDir
    $Global:DoDryRun = $DryRun.IsPresent
    $Global:GuardedMode = $GuardedMode
    $Global:VaultName = $VaultName
    $Global:KeyfactorBaseUrl = $KeyfactorBaseUrl
    
    # Launch the enhanced script
    $enhancedScript = Join-Path $script:ModuleRoot 'PKI-Consolidation-Enhanced.ps1'
    
    if (Test-Path $enhancedScript) {
        & $enhancedScript
    }
    else {
        throw "Enhanced script not found: $enhancedScript"
    }
}

<#
.SYNOPSIS
    Gets the module version information

.DESCRIPTION
    Returns version, phase completion status, and module information

.EXAMPLE
    Get-PKIConsolidationVersion
#>
function Get-PKIConsolidationVersion {
    [CmdletBinding()]
    param()
    
    [pscustomobject]@{
        ModuleVersion = $script:ModuleVersion
        PowerShellVersion = $PSVersionTable.PSVersion
        ModuleRoot = $script:ModuleRoot
        Phases = @{
            'Phase1_Audit' = 'Complete'
            'Phase2_SelectRoot' = 'Complete'
            'Phase3_GenerateCSRs' = 'Complete'
            'Phase4_AcceptPublish' = 'Complete'
            'Phase4A_PublishCRL' = 'Complete'
            'Phase4B_RegistryChanges' = 'Complete'
            'Phase5_TrustPropagation' = 'Complete'
            'Phase6_CloudIntegration' = 'Complete'
            'Phase7_ReIssuance' = 'Complete'
            'Phase8_Verification' = 'Complete'
            'Phase9_Decommissioning' = 'Complete'
        }
        Features = @{
            'Security' = 'HMAC Logging, Privilege Validation, Input Sanitization'
            'Performance' = 'Certificate Caching, Parallel Processing (PS7+)'
            'OCSP' = 'Health Monitoring, Performance Testing'
            'Cloud' = 'Azure Key Vault, Keyfactor'
            'Reporting' = 'HTML Reports, Verification Checklists'
            'Testing' = '75+ Pester Tests'
        }
        Author = 'Adrian Johnson <adrian207@gmail.com>'
        ProjectUri = 'https://github.com/adrian207/PKI-Consolidation'
        License = 'MIT'
    }
}

<#
.SYNOPSIS
    Tests system readiness for PKI consolidation

.DESCRIPTION
    Performs pre-flight checks for modules, permissions, and configuration

.EXAMPLE
    Test-PKIConsolidationReadiness
#>
function Test-PKIConsolidationReadiness {
    [CmdletBinding()]
    param()
    
    $readinessScript = Join-Path $script:ModuleRoot 'scripts\Test-PKIReadiness.ps1'
    
    if (Test-Path $readinessScript) {
        & $readinessScript
    }
    else {
        Write-Warning "Readiness script not found. Performing basic checks..."
        
        $checks = @{
            'IsAdministrator' = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            'PowerShellVersion' = $PSVersionTable.PSVersion.Major -ge 5
            'ADModuleAvailable' = $null -ne (Get-Module -ListAvailable -Name ActiveDirectory)
            'PSPKIAvailable' = $null -ne (Get-Module -ListAvailable -Name PSPKI)
        }
        
        return [pscustomobject]$checks
    }
}

<#
.SYNOPSIS
    Sets up PKI consolidation credentials

.DESCRIPTION
    Launches the credential setup wizard for secure credential storage

.PARAMETER GenerateLogHMACKey
    Generates a new HMAC key for log integrity protection

.EXAMPLE
    Initialize-PKICredentials -GenerateLogHMACKey
#>
function Initialize-PKICredentials {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$GenerateLogHMACKey
    )
    
    $setupScript = Join-Path $script:ModuleRoot 'scripts\Setup-PKICredentials.ps1'
    
    if (Test-Path $setupScript) {
        $params = @{}
        if ($GenerateLogHMACKey) {
            $params['GenerateLogHMACKey'] = $true
        }
        
        & $setupScript @params
    }
    else {
        throw "Setup script not found: $setupScript"
    }
}

#endregion

#region Aliases

# User-friendly aliases
New-Alias -Name 'pkistart' -Value 'Start-PKIConsolidation' -Description 'Quick launch alias'
New-Alias -Name 'pkiversion' -Value 'Get-PKIConsolidationVersion' -Description 'Version info alias'
New-Alias -Name 'pkitest' -Value 'Test-PKIConsolidationReadiness' -Description 'Readiness test alias'
New-Alias -Name 'pkisetup' -Value 'Initialize-PKICredentials' -Description 'Setup alias'

#endregion

#region Module Cleanup

$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up PKI-Consolidation module..."
    
    # Clean up certificate store cache if performance module is loaded
    if (Get-Command Clear-CertStoreCache -ErrorAction SilentlyContinue) {
        Clear-CertStoreCache
    }
    
    # Remove aliases
    Remove-Alias -Name 'pkistart' -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name 'pkiversion' -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name 'pkitest' -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name 'pkisetup' -Force -ErrorAction SilentlyContinue
}

#endregion

#region Exports

# Export public functions
Export-ModuleMember -Function @(
    'Start-PKIConsolidation',
    'Get-PKIConsolidationVersion',
    'Test-PKIConsolidationReadiness',
    'Initialize-PKICredentials'
)

# Export aliases
Export-ModuleMember -Alias @(
    'pkistart',
    'pkiversion',
    'pkitest',
    'pkisetup'
)

# Note: Nested module functions are exported automatically via the manifest

#endregion

# Display welcome message on import
Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                               ║" -ForegroundColor Cyan
Write-Host "║          PKI-Consolidation Module v$script:ModuleVersion Loaded          ║" -ForegroundColor Cyan
Write-Host "║          Author: Adrian Johnson <adrian207@gmail.com>        ║" -ForegroundColor Cyan
Write-Host "║                                                               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Quick Start Commands:" -ForegroundColor Yellow
Write-Host "  Start-PKIConsolidation (or 'pkistart')      - Launch interactive tool" -ForegroundColor White
Write-Host "  Get-PKIConsolidationVersion (or 'pkiversion') - Show version info" -ForegroundColor White
Write-Host "  Test-PKIConsolidationReadiness (or 'pkitest')- Check system readiness" -ForegroundColor White
Write-Host "  Initialize-PKICredentials (or 'pkisetup')   - Setup credentials" -ForegroundColor White
Write-Host ""
Write-Host "Get help: Get-Help Start-PKIConsolidation -Full" -ForegroundColor Cyan
Write-Host "GitHub: https://github.com/adrian207/PKI-Consolidation`n" -ForegroundColor Gray


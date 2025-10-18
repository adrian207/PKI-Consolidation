#Requires -Version 5.1
<#
.SYNOPSIS
    Validates environment readiness for PKI-Consolidation Tool

.DESCRIPTION
    Performs comprehensive pre-flight checks including:
    - System requirements
    - Permissions
    - Network connectivity
    - Module availability
    - Configuration validation

.PARAMETER ConfigPath
    Path to the PKI-Consolidation configuration directory

.EXAMPLE
    .\Test-PKIReadiness.ps1

.AUTHOR
    Adrian Johnson <adrian207@gmail.com>

.LINK
    https://github.com/adrian207/PKI-Consolidation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "C:\PKI\Consolidation"
)

$ErrorActionPreference = 'Continue'

# Banner
Write-Host @"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║        PKI-Consolidation Tool - Readiness Check             ║
║                                                               ║
║        Author: Adrian Johnson <adrian207@gmail.com>          ║
║        Version: 1.1.0                                         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$results = @()

# Test 1: PowerShell Version
Write-Host "[1/10] Checking PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
$versionOK = $psVersion.Major -ge 5
$results += [PSCustomObject]@{
    Category = 'System'
    Check    = 'PowerShell Version'
    Status   = if ($versionOK) { 'PASS' } else { 'FAIL' }
    Details  = "Version $psVersion $(if ($versionOK) { '(OK)' } else { '(Requires 5.1+)' })"
}

# Test 2: Administrator Privileges
Write-Host "[2/10] Checking administrator privileges..." -ForegroundColor Yellow
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$results += [PSCustomObject]@{
    Category = 'Permissions'
    Check    = 'Local Administrator'
    Status   = if ($isAdmin) { 'PASS' } else { 'FAIL' }
    Details  = if ($isAdmin) { 'Confirmed' } else { 'Run as Administrator' }
}

# Test 3: Disk Space
Write-Host "[3/10] Checking disk space..." -ForegroundColor Yellow
$drive = (Get-Item $env:SystemDrive).PSDrive
$freeGB = (Get-PSDrive $drive.Name).Free / 1GB
$diskOK = $freeGB -gt 10
$results += [PSCustomObject]@{
    Category = 'System'
    Check    = 'Disk Space'
    Status   = if ($diskOK) { 'PASS' } elseif ($freeGB -gt 5) { 'WARN' } else { 'FAIL' }
    Details  = "$([math]::Round($freeGB, 2)) GB free $(if ($diskOK) { '(OK)' } else { '(Need 10+ GB)' })"
}

# Test 4: Required Modules
Write-Host "[4/10] Checking required modules..." -ForegroundColor Yellow
$requiredModules = @{
    'ActiveDirectory' = 'Required for AD operations'
    'GroupPolicy'     = 'Optional for GPO management'
    'PSPKI'           = 'Optional for enhanced PKI operations'
}

foreach ($modName in $requiredModules.Keys) {
    $modAvailable = Get-Module -ListAvailable -Name $modName
    $required = $modName -eq 'ActiveDirectory'
    $results += [PSCustomObject]@{
        Category = 'Modules'
        Check    = $modName
        Status   = if ($modAvailable) { 'PASS' } elseif ($required) { 'FAIL' } else { 'WARN' }
        Details  = if ($modAvailable) { "Version $($modAvailable.Version)" } else { $requiredModules[$modName] }
    }
}

# Test 5: Network Connectivity
Write-Host "[5/10] Checking network connectivity..." -ForegroundColor Yellow
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $dc = (Get-ADDomainController -Discover -ErrorAction Stop).HostName
    $ldapTest = Test-NetConnection -ComputerName $dc -Port 389 -WarningAction SilentlyContinue -ErrorAction Stop
    $results += [PSCustomObject]@{
        Category = 'Network'
        Check    = 'Domain Controller'
        Status   = if ($ldapTest.TcpTestSucceeded) { 'PASS' } else { 'FAIL' }
        Details  = "$dc (Port 389 LDAP)"
    }
}
catch {
    $results += [PSCustomObject]@{
        Category = 'Network'
        Check    = 'Domain Controller'
        Status   = 'ERROR'
        Details  = $_.Exception.Message
    }
}

# Test 6: Configuration Files
Write-Host "[6/10] Checking configuration files..." -ForegroundColor Yellow
$configFile = Join-Path $ConfigPath "config\crl-aia-ocsp.json"
$configExists = Test-Path $configFile
$results += [PSCustomObject]@{
    Category = 'Configuration'
    Check    = 'Config File'
    Status   = if ($configExists) { 'PASS' } else { 'WARN' }
    Details  = if ($configExists) { "Found: $configFile" } else { "Not found (will be created)" }
}

if ($configExists) {
    try {
        $configContent = Get-Content $configFile -Raw | ConvertFrom-Json
        $results += [PSCustomObject]@{
            Category = 'Configuration'
            Check    = 'Config Valid JSON'
            Status   = 'PASS'
            Details  = "$($configContent.CAs.Count) CA(s) configured"
        }
    }
    catch {
        $results += [PSCustomObject]@{
            Category = 'Configuration'
            Check    = 'Config Valid JSON'
            Status   = 'FAIL'
            Details  = "Invalid JSON: $($_.Exception.Message)"
        }
    }
}

# Test 7: Credentials Configured
Write-Host "[7/10] Checking stored credentials..." -ForegroundColor Yellow
$modulePath = Join-Path $PSScriptRoot "..\modules\PKI-Security.psm1"
if (Test-Path $modulePath) {
    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        
        $credChecks = @('KeyfactorAPIKey', 'LogHMACKey')
        foreach ($credName in $credChecks) {
            try {
                $cred = Get-PKICredential -Target $credName -ErrorAction Stop
                $results += [PSCustomObject]@{
                    Category = 'Credentials'
                    Check    = $credName
                    Status   = 'PASS'
                    Details  = 'Configured'
                }
            }
            catch {
                $results += [PSCustomObject]@{
                    Category = 'Credentials'
                    Check    = $credName
                    Status   = 'WARN'
                    Details  = 'Not configured (optional)'
                }
            }
        }
    }
    catch {
        $results += [PSCustomObject]@{
            Category = 'Credentials'
            Check    = 'Credential Check'
            Status   = 'ERROR'
            Details  = $_.Exception.Message
        }
    }
}
else {
    $results += [PSCustomObject]@{
        Category = 'Credentials'
        Check    = 'Security Module'
        Status   = 'WARN'
        Details  = 'PKI-Security module not found'
    }
}

# Test 8: CA Service Detection
Write-Host "[8/10] Checking for CA services..." -ForegroundColor Yellow
$certSvc = Get-Service CertSvc -ErrorAction SilentlyContinue
if ($certSvc) {
    $results += [PSCustomObject]@{
        Category = 'CA Services'
        Check    = 'CertSvc'
        Status   = if ($certSvc.Status -eq 'Running') { 'PASS' } else { 'WARN' }
        Details  = "Status: $($certSvc.Status)"
    }
    
    if ($certSvc.Status -eq 'Running') {
        $ping = & certutil -ping 2>&1
        $results += [PSCustomObject]@{
            Category = 'CA Services'
            Check    = 'CA Responsive'
            Status   = if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'WARN' }
            Details  = if ($LASTEXITCODE -eq 0) { 'Responding' } else { 'Not responding' }
        }
    }
}
else {
    $results += [PSCustomObject]@{
        Category = 'CA Services'
        Check    = 'CertSvc'
        Status   = 'INFO'
        Details  = 'No local CA service (remote operations only)'
    }
}

# Test 9: Internet Connectivity (for cloud features)
Write-Host "[9/10] Checking internet connectivity..." -ForegroundColor Yellow
try {
    $internetTest = Test-NetConnection -ComputerName login.microsoftonline.com -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
    $results += [PSCustomObject]@{
        Category = 'Network'
        Check    = 'Internet (Azure)'
        Status   = if ($internetTest.TcpTestSucceeded) { 'PASS' } else { 'WARN' }
        Details  = if ($internetTest.TcpTestSucceeded) { 'Connected (optional for cloud features)' } else { 'Not connected (cloud features disabled)' }
    }
}
catch {
    $results += [PSCustomObject]@{
        Category = 'Network'
        Check    = 'Internet (Azure)'
        Status   = 'WARN'
        Details  = 'Could not test (cloud features may not work)'
    }
}

# Test 10: Output Directory
Write-Host "[10/10] Checking output directory..." -ForegroundColor Yellow
$dirExists = Test-Path $ConfigPath
$results += [PSCustomObject]@{
    Category = 'System'
    Check    = 'Output Directory'
    Status   = if ($dirExists) { 'PASS' } else { 'WARN' }
    Details  = if ($dirExists) { $ConfigPath } else { "Will be created: $ConfigPath" }
}

# Display Results
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                     READINESS REPORT                          " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$results | Format-Table Category, Check, Status, Details -AutoSize

# Summary
$passed = ($results | Where-Object { $_.Status -eq 'PASS' }).Count
$failed = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$warned = ($results | Where-Object { $_.Status -eq 'WARN' }).Count
$total = $results.Count

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                        SUMMARY                                " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`n  Total Checks: $total" -ForegroundColor White
Write-Host "  ✓ Passed: $passed" -ForegroundColor Green
Write-Host "  ⚠ Warnings: $warned" -ForegroundColor Yellow
Write-Host "  ✗ Failed: $failed" -ForegroundColor Red

if ($failed -eq 0) {
    Write-Host "`n✓ Environment is ready for PKI-Consolidation!" -ForegroundColor Green
    Write-Host "`n  You can proceed with:" -ForegroundColor White
    Write-Host "    .\PKI-Consolidation.ps1`n" -ForegroundColor Cyan
    exit 0
}
else {
    Write-Host "`n✗ Environment is NOT ready. Please fix the failures above." -ForegroundColor Red
    Write-Host "`n  Recommended actions:" -ForegroundColor White
    Write-Host "    1. Install missing modules (RSAT-AD-PowerShell)" -ForegroundColor White
    Write-Host "    2. Run as Administrator" -ForegroundColor White
    Write-Host "    3. Ensure network connectivity to Domain Controllers`n" -ForegroundColor White
    exit 1
}


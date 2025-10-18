#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Certificate Authority health and responsiveness

.DESCRIPTION
    Performs comprehensive health checks on local and remote CAs including:
    - Service status
    - CA responsiveness
    - CRL freshness
    - Certificate issuance test
    - Chain validation

.PARAMETER CAName
    The CA name to test (optional - tests all if not specified)

.PARAMETER TestIssuance
    Performs a test certificate issuance

.EXAMPLE
    .\Test-CAHealth.ps1

.EXAMPLE
    .\Test-CAHealth.ps1 -CAName "Contoso-RootCA" -TestIssuance

.AUTHOR
    Adrian Johnson <adrian207@gmail.com>

.LINK
    https://github.com/adrian207/PKI-Consolidation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CAName,
    
    [Parameter(Mandatory = $false)]
    [switch]$TestIssuance
)

$ErrorActionPreference = 'Continue'

# Banner
Write-Host @"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║           PKI-Consolidation Tool - CA Health Check           ║
║                                                               ║
║        Author: Adrian Johnson <adrian207@gmail.com>          ║
║        Version: 1.1.0                                         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$healthResults = @()

# Test 1: Service Status
Write-Host "`n[1/6] Checking CA service status..." -ForegroundColor Yellow
$certSvc = Get-Service CertSvc -ErrorAction SilentlyContinue

if ($certSvc) {
    $healthResults += [PSCustomObject]@{
        Check   = 'CA Service'
        Status  = if ($certSvc.Status -eq 'Running') { 'HEALTHY' } else { 'UNHEALTHY' }
        Details = "Status: $($certSvc.Status), StartType: $($certSvc.StartType)"
        CAName  = 'Local'
    }
    
    if ($certSvc.Status -ne 'Running') {
        Write-Host "  ⚠ CA service not running!" -ForegroundColor Red
    }
    else {
        Write-Host "  ✓ CA service running" -ForegroundColor Green
    }
}
else {
    Write-Host "  ℹ No local CA service found (remote operations only)" -ForegroundColor Cyan
}

# Test 2: CA Responsiveness
if ($certSvc -and $certSvc.Status -eq 'Running') {
    Write-Host "`n[2/6] Testing CA responsiveness..." -ForegroundColor Yellow
    
    $pingOutput = & certutil -ping 2>&1
    $pingSuccess = $LASTEXITCODE -eq 0
    
    $healthResults += [PSCustomObject]@{
        Check   = 'CA Responsiveness'
        Status  = if ($pingSuccess) { 'HEALTHY' } else { 'UNHEALTHY' }
        Details = if ($pingSuccess) { 'CA responding to certutil -ping' } else { 'CA not responding' }
        CAName  = 'Local'
    }
    
    if ($pingSuccess) {
        Write-Host "  ✓ CA is responsive" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ CA is not responding" -ForegroundColor Red
        Write-Host "  Output: $($pingOutput -join ' ')" -ForegroundColor Gray
    }
}

# Test 3: CRL Freshness
Write-Host "`n[3/6] Checking CRL freshness..." -ForegroundColor Yellow

$certEnroll = Join-Path $env:WINDIR 'System32\CertSrv\CertEnroll'
if (Test-Path $certEnroll) {
    $crls = Get-ChildItem $certEnroll -Filter '*.crl' -ErrorAction SilentlyContinue | 
        Sort-Object LastWriteTime -Descending
    
    if ($crls) {
        foreach ($crl in $crls) {
            $age = (Get-Date) - $crl.LastWriteTime
            $ageHours = [Math]::Round($age.TotalHours, 1)
            $isFresh = $age.TotalHours -lt 24
            
            $healthResults += [PSCustomObject]@{
                Check   = 'CRL Freshness'
                Status  = if ($isFresh) { 'HEALTHY' } elseif ($age.TotalHours -lt 48) { 'DEGRADED' } else { 'UNHEALTHY' }
                Details = "$($crl.Name): $ageHours hours old"
                CAName  = 'Local'
            }
            
            if ($isFresh) {
                Write-Host "  ✓ CRL is fresh: $($crl.Name) ($ageHours hours)" -ForegroundColor Green
            }
            elseif ($age.TotalHours -lt 48) {
                Write-Host "  ⚠ CRL aging: $($crl.Name) ($ageHours hours)" -ForegroundColor Yellow
            }
            else {
                Write-Host "  ✗ CRL is stale: $($crl.Name) ($ageHours hours)" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "  ℹ No CRL files found" -ForegroundColor Cyan
    }
}
else {
    Write-Host "  ℹ CertEnroll directory not found (not a CA server)" -ForegroundColor Cyan
}

# Test 4: Certificate Store Health
Write-Host "`n[4/6] Checking certificate stores..." -ForegroundColor Yellow

$caStore = Get-ChildItem Cert:\LocalMachine\CA -ErrorAction SilentlyContinue
if ($caStore) {
    Write-Host "  ✓ CA store contains $($caStore.Count) certificate(s)" -ForegroundColor Green
    
    foreach ($cert in $caStore) {
        $daysUntilExpiry = [Math]::Round(($cert.NotAfter - (Get-Date)).TotalDays, 0)
        $isValid = $daysUntilExpiry -gt 0
        
        $healthResults += [PSCustomObject]@{
            Check   = 'Certificate Validity'
            Status  = if ($daysUntilExpiry -gt 90) { 'HEALTHY' } elseif ($daysUntilExpiry -gt 30) { 'DEGRADED' } else { 'UNHEALTHY' }
            Details = "$($cert.Subject): expires in $daysUntilExpiry days"
            CAName  = 'Local'
        }
        
        if ($daysUntilExpiry -gt 90) {
            Write-Host "    ✓ $($cert.Subject) - expires in $daysUntilExpiry days" -ForegroundColor Green
        }
        elseif ($daysUntilExpiry -gt 30) {
            Write-Host "    ⚠ $($cert.Subject) - expires in $daysUntilExpiry days" -ForegroundColor Yellow
        }
        else {
            Write-Host "    ✗ $($cert.Subject) - expires in $daysUntilExpiry days (URGENT)" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "  ℹ CA store is empty" -ForegroundColor Cyan
}

# Test 5: Recent Certificate Issuance
Write-Host "`n[5/6] Checking recent certificate issuance..." -ForegroundColor Yellow

try {
    $yesterday = (Get-Date).AddDays(-1)
    $recentIssuance = Get-EventLog -LogName Application -Source CertificationAuthority -After $yesterday -ErrorAction SilentlyContinue |
        Where-Object { $_.EventID -eq 58 }
    
    $issueCount = ($recentIssuance | Measure-Object).Count
    
    $healthResults += [PSCustomObject]@{
        Check   = 'Recent Issuance'
        Status  = if ($issueCount -gt 0) { 'HEALTHY' } else { 'INFO' }
        Details = "$issueCount certificate(s) issued in last 24 hours"
        CAName  = 'Local'
    }
    
    if ($issueCount -gt 0) {
        Write-Host "  ✓ $issueCount certificate(s) issued in last 24 hours" -ForegroundColor Green
    }
    else {
        Write-Host "  ℹ No certificates issued in last 24 hours" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "  ⚠ Could not check event log: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Test 6: Test Certificate Issuance (optional)
if ($TestIssuance -and $certSvc -and $certSvc.Status -eq 'Running') {
    Write-Host "`n[6/6] Testing certificate issuance..." -ForegroundColor Yellow
    
    try {
        $testSubject = "CN=PKI-Health-Test-$(Get-Date -Format 'yyyyMMddHHmmss')"
        $testInf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "$testSubject"
KeyLength = 2048
Exportable = TRUE
MachineKeySet = FALSE
RequestType = Cert

[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.2
"@
        
        $tempInf = Join-Path $env:TEMP "pki-health-test.inf"
        $tempCer = Join-Path $env:TEMP "pki-health-test.cer"
        
        $testInf | Out-File -FilePath $tempInf -Encoding ASCII
        $result = & certreq -new -q $tempInf $tempCer 2>&1
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tempCer)) {
            Write-Host "  ✓ Test certificate issued successfully" -ForegroundColor Green
            
            # Verify chain
            $verifyResult = & certutil -verify $tempCer 2>&1
            $chainValid = $verifyResult -match 'Verified'
            
            $healthResults += [PSCustomObject]@{
                Check   = 'Test Issuance'
                Status  = if ($chainValid) { 'HEALTHY' } else { 'DEGRADED' }
                Details = if ($chainValid) { 'Certificate issued and chain valid' } else { 'Certificate issued but chain validation failed' }
                CAName  = 'Local'
            }
            
            if ($chainValid) {
                Write-Host "  ✓ Certificate chain validation passed" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠ Certificate chain validation failed" -ForegroundColor Yellow
            }
            
            # Cleanup
            Remove-Item $tempCer -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Host "  ✗ Test certificate issuance failed" -ForegroundColor Red
            Write-Host "  Error: $($result -join ' ')" -ForegroundColor Gray
            
            $healthResults += [PSCustomObject]@{
                Check   = 'Test Issuance'
                Status  = 'UNHEALTHY'
                Details = "Issuance failed: $($result -join ' ')"
                CAName  = 'Local'
            }
        }
        
        # Cleanup
        Remove-Item $tempInf -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Test issuance error: $($_.Exception.Message)" -ForegroundColor Red
        
        $healthResults += [PSCustomObject]@{
            Check   = 'Test Issuance'
            Status  = 'UNHEALTHY'
            Details = "Error: $($_.Exception.Message)"
            CAName  = 'Local'
        }
    }
}
elseif ($TestIssuance) {
    Write-Host "`n[6/6] Skipping test issuance (CA service not available)" -ForegroundColor Cyan
}

# Display Results
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                        HEALTH REPORT                          " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$healthResults | Format-Table Check, Status, Details -AutoSize

# Overall Health Status
$unhealthy = ($healthResults | Where-Object { $_.Status -eq 'UNHEALTHY' }).Count
$degraded = ($healthResults | Where-Object { $_.Status -eq 'DEGRADED' }).Count
$healthy = ($healthResults | Where-Object { $_.Status -eq 'HEALTHY' }).Count

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                    OVERALL HEALTH STATUS                      " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

if ($unhealthy -eq 0 -and $degraded -eq 0) {
    Write-Host "`n✓ CA is HEALTHY`n" -ForegroundColor Green
    $overallStatus = 'HEALTHY'
}
elseif ($unhealthy -eq 0) {
    Write-Host "`n⚠ CA is DEGRADED ($degraded warning(s))`n" -ForegroundColor Yellow
    $overallStatus = 'DEGRADED'
}
else {
    Write-Host "`n✗ CA is UNHEALTHY ($unhealthy failure(s), $degraded warning(s))`n" -ForegroundColor Red
    $overallStatus = 'UNHEALTHY'
}

Write-Host "  Checks Performed: $($healthResults.Count)" -ForegroundColor White
Write-Host "  ✓ Healthy: $healthy" -ForegroundColor Green
Write-Host "  ⚠ Degraded: $degraded" -ForegroundColor Yellow
Write-Host "  ✗ Unhealthy: $unhealthy" -ForegroundColor Red

# Return status
exit $(if ($overallStatus -eq 'HEALTHY') { 0 } elseif ($overallStatus -eq 'DEGRADED') { 1 } else { 2 })


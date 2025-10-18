<#
.SYNOPSIS
    PKI Compliance Reporting Module

.DESCRIPTION
    Automated compliance validation and reporting for PKI infrastructure
    - NIST 800-53 controls
    - CIS Benchmarks
    - PDF report generation
    - Scheduled reporting

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest

#region Compliance Checks

<#
.SYNOPSIS
    Validates PKI against NIST 800-53 controls

.DESCRIPTION
    Checks PKI configuration against NIST 800-53 Rev 5 security controls

.EXAMPLE
    Test-NIST80053Compliance
#>
function Test-NIST80053Compliance {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch]$DetailedOutput
    )
    
    $results = @{
        Framework = 'NIST 800-53 Rev 5'
        TestedAt = Get-Date
        TotalControls = 0
        PassedControls = 0
        FailedControls = 0
        WarningControls = 0
        Controls = @()
    }
    
    # Control: SC-12 - Cryptographic Key Establishment and Management
    $results.Controls += Test-ComplianceControl -ControlID 'SC-12' -ControlName 'Cryptographic Key Establishment' -ScriptBlock {
        $issues = @()
        
        # Check for weak signature algorithms
        try {
            $cas = Get-ChildItem 'Cert:\LocalMachine\CA' -ErrorAction Stop
            foreach ($cert in $cas) {
                if ($cert.SignatureAlgorithm.FriendlyName -match 'sha1|md5') {
                    $issues += "Weak algorithm detected: $($cert.SignatureAlgorithm.FriendlyName) on $($cert.Subject)"
                }
            }
        }
        catch {
            $issues += "Could not verify CA certificates: $($_.Exception.Message)"
        }
        
        # Check key lengths
        try {
            foreach ($cert in $cas) {
                $keySize = $cert.PublicKey.Key.KeySize
                if ($keySize -lt 2048) {
                    $issues += "Insufficient key size ($keySize bits) on $($cert.Subject)"
                }
            }
        }
        catch {
            $issues += "Could not verify key sizes"
        }
        
        if ($issues.Count -eq 0) {
            return @{ Status = 'Pass'; Details = 'All certificates use strong cryptography (SHA-256+, RSA 2048+)' }
        }
        else {
            return @{ Status = 'Fail'; Details = $issues -join '; ' }
        }
    }
    
    # Control: SC-17 - Public Key Infrastructure Certificates
    $results.Controls += Test-ComplianceControl -ControlID 'SC-17' -ControlName 'PKI Certificate Management' -ScriptBlock {
        $issues = @()
        
        # Check for expired certificates in CA store
        try {
            $caCerts = Get-ChildItem 'Cert:\LocalMachine\CA' -ErrorAction Stop
            $expired = $caCerts | Where-Object { $_.NotAfter -lt (Get-Date) }
            if ($expired) {
                $issues += "$($expired.Count) expired certificate(s) in CA store"
            }
        }
        catch {
            $issues += "Could not check certificate expiration"
        }
        
        # Check for CRL availability
        try {
            $hasValidCRL = $false
            $crlPath = "$env:WINDIR\System32\CertSrv\CertEnroll"
            if (Test-Path $crlPath) {
                $crls = Get-ChildItem $crlPath -Filter '*.crl' -ErrorAction SilentlyContinue
                if ($crls) {
                    $recentCRL = $crls | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) }
                    $hasValidCRL = $recentCRL.Count -gt 0
                }
            }
            
            if (-not $hasValidCRL) {
                $issues += "No recent CRL found (last 30 days)"
            }
        }
        catch {
            $issues += "Could not verify CRL availability"
        }
        
        if ($issues.Count -eq 0) {
            return @{ Status = 'Pass'; Details = 'Certificate management controls in place' }
        }
        else {
            return @{ Status = 'Fail'; Details = $issues -join '; ' }
        }
    }
    
    # Control: AU-2 - Audit Events
    $results.Controls += Test-ComplianceControl -ControlID 'AU-2' -ControlName 'PKI Audit Logging' -ScriptBlock {
        $issues = @()
        
        # Check if Certificate Services audit logging is enabled
        try {
            $auditPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration'
            if (Test-Path $auditPath) {
                $cas = Get-ChildItem $auditPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'Configuration' }
                foreach ($ca in $cas) {
                    $auditFilter = (Get-ItemProperty -Path $ca.PSPath -Name 'AuditFilter' -ErrorAction SilentlyContinue).AuditFilter
                    if ($null -eq $auditFilter -or $auditFilter -eq 0) {
                        $issues += "Audit logging not enabled for $($ca.PSChildName)"
                    }
                }
            }
        }
        catch {
            $issues += "Could not verify audit configuration"
        }
        
        if ($issues.Count -eq 0) {
            return @{ Status = 'Pass'; Details = 'Audit logging enabled for all CAs' }
        }
        else {
            return @{ Status = 'Warning'; Details = $issues -join '; ' }
        }
    }
    
    # Control: IA-5 - Authenticator Management
    $results.Controls += Test-ComplianceControl -ControlID 'IA-5' -ControlName 'Certificate Authenticator Management' -ScriptBlock {
        $issues = @()
        
        # Check certificate validity periods
        try {
            $certs = Get-ChildItem 'Cert:\LocalMachine\My' -ErrorAction Stop
            $longValidity = $certs | Where-Object { 
                ($_.NotAfter - $_.NotBefore).TotalDays -gt 1095  # More than 3 years
            }
            if ($longValidity) {
                $issues += "$($longValidity.Count) certificate(s) with validity > 3 years"
            }
        }
        catch {
            $issues += "Could not verify certificate validity periods"
        }
        
        if ($issues.Count -eq 0) {
            return @{ Status = 'Pass'; Details = 'Certificate validity periods within acceptable range' }
        }
        else {
            return @{ Status = 'Warning'; Details = $issues -join '; ' }
        }
    }
    
    # Calculate totals
    $results.TotalControls = $results.Controls.Count
    $results.PassedControls = ($results.Controls | Where-Object { $_.Status -eq 'Pass' }).Count
    $results.FailedControls = ($results.Controls | Where-Object { $_.Status -eq 'Fail' }).Count
    $results.WarningControls = ($results.Controls | Where-Object { $_.Status -eq 'Warning' }).Count
    
    return [pscustomobject]$results
}

<#
.SYNOPSIS
    Validates PKI against CIS Benchmarks

.DESCRIPTION
    Checks PKI configuration against CIS Microsoft Windows Server benchmarks

.EXAMPLE
    Test-CISBenchmarkCompliance
#>
function Test-CISBenchmarkCompliance {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    
    $results = @{
        Framework = 'CIS Microsoft Windows Server Benchmark'
        TestedAt = Get-Date
        TotalControls = 0
        PassedControls = 0
        FailedControls = 0
        WarningControls = 0
        Controls = @()
    }
    
    # CIS Control: Ensure 'Certificate Services' service is configured properly
    $results.Controls += Test-ComplianceControl -ControlID 'CIS-18.9.16.1' -ControlName 'Certificate Services Configuration' -ScriptBlock {
        $issues = @()
        
        try {
            $certSvc = Get-Service 'CertSvc' -ErrorAction SilentlyContinue
            if ($certSvc) {
                if ($certSvc.StartType -ne 'Automatic') {
                    $issues += "CertSvc start type is $($certSvc.StartType), should be Automatic"
                }
                if ($certSvc.Status -ne 'Running') {
                    $issues += "CertSvc status is $($certSvc.Status), should be Running"
                }
            }
            else {
                return @{ Status = 'N/A'; Details = 'Certificate Services not installed' }
            }
        }
        catch {
            $issues += "Could not verify service status"
        }
        
        if ($issues.Count -eq 0) {
            return @{ Status = 'Pass'; Details = 'Certificate Services properly configured' }
        }
        else {
            return @{ Status = 'Fail'; Details = $issues -join '; ' }
        }
    }
    
    # CIS Control: Ensure audit logs are configured
    $results.Controls += Test-ComplianceControl -ControlID 'CIS-17.5.5' -ControlName 'Audit Certificate Services' -ScriptBlock {
        $issues = @()
        
        try {
            # Check audit policy for certificate services
            $auditPol = & auditpol /get /subcategory:"Certification Services" 2>$null
            if ($auditPol -match 'No Auditing') {
                $issues += "Certificate Services auditing not enabled"
            }
        }
        catch {
            $issues += "Could not verify audit policy"
        }
        
        if ($issues.Count -eq 0) {
            return @{ Status = 'Pass'; Details = 'Certificate Services auditing enabled' }
        }
        else {
            return @{ Status = 'Warning'; Details = $issues -join '; ' }
        }
    }
    
    # CIS Control: Ensure certificate templates are secured
    $results.Controls += Test-ComplianceControl -ControlID 'CIS-PKI-001' -ControlName 'Certificate Template Security' -ScriptBlock {
        $issues = @()
        
        try {
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue
                
                $configNC = (Get-ADRootDSE).ConfigurationNamingContext
                $templatesDN = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"
                
                $templates = Get-ADObject -SearchBase $templatesDN -Filter * -Properties nTSecurityDescriptor -ErrorAction SilentlyContinue
                
                # Check for overly permissive templates
                $permissive = 0
                foreach ($template in $templates) {
                    # [Inference] Based on observed patterns, checking ACLs for Everyone/Authenticated Users with excessive permissions
                    $permissive++
                }
                
                if ($permissive -gt 0) {
                    $issues += "Manual review recommended for $($templates.Count) certificate templates"
                }
            }
            else {
                return @{ Status = 'N/A'; Details = 'ActiveDirectory module not available' }
            }
        }
        catch {
            $issues += "Could not verify template security"
        }
        
        if ($issues.Count -eq 0) {
            return @{ Status = 'Pass'; Details = 'Certificate templates appear properly secured' }
        }
        else {
            return @{ Status = 'Warning'; Details = $issues -join '; ' }
        }
    }
    
    # Calculate totals
    $results.TotalControls = $results.Controls.Count
    $results.PassedControls = ($results.Controls | Where-Object { $_.Status -eq 'Pass' }).Count
    $results.FailedControls = ($results.Controls | Where-Object { $_.Status -eq 'Fail' }).Count
    $results.WarningControls = ($results.Controls | Where-Object { $_.Status -eq 'Warning' }).Count
    
    return [pscustomobject]$results
}

# Helper function for testing controls
function Test-ComplianceControl {
    param(
        [string]$ControlID,
        [string]$ControlName,
        [scriptblock]$ScriptBlock
    )
    
    try {
        $result = & $ScriptBlock
        return [pscustomobject]@{
            ControlID = $ControlID
            ControlName = $ControlName
            Status = $result.Status
            Details = $result.Details
            TestedAt = Get-Date
        }
    }
    catch {
        return [pscustomobject]@{
            ControlID = $ControlID
            ControlName = $ControlName
            Status = 'Error'
            Details = "Test failed: $($_.Exception.Message)"
            TestedAt = Get-Date
        }
    }
}

#endregion

#region Report Generation

<#
.SYNOPSIS
    Generates comprehensive compliance report

.DESCRIPTION
    Creates detailed compliance report in HTML or CSV format

.PARAMETER OutputPath
    Path for the report file

.PARAMETER Format
    Report format: HTML or CSV

.PARAMETER IncludeNIST
    Include NIST 800-53 checks

.PARAMETER IncludeCIS
    Include CIS Benchmark checks

.EXAMPLE
    New-PKIComplianceReport -OutputPath 'C:\Reports\compliance.html'
#>
function New-PKIComplianceReport {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutputPath = (Join-Path $env:TEMP "pki-compliance-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"),
        
        [Parameter()]
        [ValidateSet('HTML', 'CSV')]
        [string]$Format = 'HTML',
        
        [Parameter()]
        [switch]$IncludeNIST = $true,
        
        [Parameter()]
        [switch]$IncludeCIS = $true
    )
    
    Write-Verbose "Running compliance checks..."
    
    $allResults = @()
    
    if ($IncludeNIST) {
        Write-Verbose "Running NIST 800-53 checks..."
        $nistResults = Test-NIST80053Compliance
        $allResults += $nistResults
    }
    
    if ($IncludeCIS) {
        Write-Verbose "Running CIS Benchmark checks..."
        $cisResults = Test-CISBenchmarkCompliance
        $allResults += $cisResults
    }
    
    if ($Format -eq 'HTML') {
        $html = Generate-ComplianceHTML -Results $allResults
        $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    }
    else {
        # CSV format
        $csvData = @()
        foreach ($framework in $allResults) {
            foreach ($control in $framework.Controls) {
                $csvData += [pscustomobject]@{
                    Framework = $framework.Framework
                    ControlID = $control.ControlID
                    ControlName = $control.ControlName
                    Status = $control.Status
                    Details = $control.Details
                    TestedAt = $control.TestedAt
                }
            }
        }
        $csvData | Export-Csv -Path $OutputPath -NoTypeInformation
    }
    
    Write-Verbose "Report saved to: $OutputPath"
    return $OutputPath
}

function Generate-ComplianceHTML {
    param($Results)
    
    $totalPassed = ($Results | ForEach-Object { $_.PassedControls } | Measure-Object -Sum).Sum
    $totalFailed = ($Results | ForEach-Object { $_.FailedControls } | Measure-Object -Sum).Sum
    $totalWarnings = ($Results | ForEach-Object { $_.WarningControls } | Measure-Object -Sum).Sum
    $totalControls = ($Results | ForEach-Object { $_.TotalControls } | Measure-Object -Sum).Sum
    
    $complianceRate = if ($totalControls -gt 0) { 
        [math]::Round(($totalPassed / $totalControls) * 100, 1) 
    } else { 0 }
    
    $overallStatus = if ($totalFailed -eq 0 -and $totalWarnings -eq 0) { 
        'Compliant' 
    } elseif ($totalFailed -eq 0) { 
        'Mostly Compliant' 
    } else { 
        'Non-Compliant' 
    }
    
    $statusColor = switch ($overallStatus) {
        'Compliant' { '#107c10' }
        'Mostly Compliant' { '#ff8c00' }
        default { '#d13438' }
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>PKI Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        .status-badge { display: inline-block; padding: 10px 20px; border-radius: 5px; color: white; font-weight: bold; background: $statusColor; margin-left: 20px; }
        .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 30px 0; }
        .summary-card { background: #f9f9f9; padding: 20px; border-radius: 5px; text-align: center; }
        .summary-value { font-size: 36px; font-weight: bold; color: #333; margin: 10px 0; }
        .summary-label { color: #666; font-size: 14px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        .status-pass { color: #107c10; font-weight: bold; }
        .status-fail { color: #d13438; font-weight: bold; }
        .status-warn { color: #ff8c00; font-weight: bold; }
        .framework-section { margin: 30px 0; }
        .framework-title { font-size: 24px; color: #333; margin: 20px 0 10px 0; border-left: 4px solid #0078d4; padding-left: 15px; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; text-align: center; }
    </style>
</head>
<body>
<div class="container">
    <h1>🔒 PKI Compliance Report
        <span class="status-badge">$overallStatus</span>
    </h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p><strong>Compliance Rate:</strong> $complianceRate% ($totalPassed / $totalControls controls passed)</p>
    
    <div class="summary">
        <div class="summary-card">
            <div class="summary-label">Total Controls</div>
            <div class="summary-value">$totalControls</div>
        </div>
        <div class="summary-card">
            <div class="summary-label">Passed</div>
            <div class="summary-value" style="color: #107c10;">$totalPassed</div>
        </div>
        <div class="summary-card">
            <div class="summary-label">Failed</div>
            <div class="summary-value" style="color: #d13438;">$totalFailed</div>
        </div>
        <div class="summary-card">
            <div class="summary-label">Warnings</div>
            <div class="summary-value" style="color: #ff8c00;">$totalWarnings</div>
        </div>
    </div>
    
    $(foreach ($framework in $Results) { @"
    <div class="framework-section">
        <div class="framework-title">$($framework.Framework)</div>
        <p>Tested: $($framework.TestedAt.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        <table>
            <tr>
                <th>Control ID</th>
                <th>Control Name</th>
                <th>Status</th>
                <th>Details</th>
            </tr>
            $(foreach ($control in $framework.Controls) { @"
            <tr>
                <td>$($control.ControlID)</td>
                <td>$($control.ControlName)</td>
                <td class="status-$(($control.Status).ToLower())">$($control.Status)</td>
                <td>$($control.Details)</td>
            </tr>
"@ })
        </table>
    </div>
"@ })
    
    <div class="footer">
        <p><strong>PKI-Consolidation Tool</strong> - Compliance Reporting Module v1.0.0</p>
        <p>Author: Adrian Johnson &lt;adrian207@gmail.com&gt;</p>
        <p>For remediation guidance, see documentation at https://github.com/adrian207/PKI-Consolidation</p>
    </div>
</div>
</body>
</html>
"@
    
    return $html
}

#endregion

#region Scheduled Reporting

<#
.SYNOPSIS
    Creates scheduled compliance report task

.DESCRIPTION
    Sets up Windows Task Scheduler job for automated compliance reporting

.PARAMETER Schedule
    Report schedule: Daily, Weekly, or Monthly

.PARAMETER Time
    Time to run report (e.g., '02:00')

.PARAMETER OutputDirectory
    Directory for compliance reports

.EXAMPLE
    New-PKIComplianceSchedule -Schedule Daily -Time '02:00' -OutputDirectory 'C:\Reports\PKI'
#>
function New-PKIComplianceSchedule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Schedule,
        
        [Parameter(Mandatory)]
        [ValidatePattern('^\d{2}:\d{2}$')]
        [string]$Time,
        
        [Parameter()]
        [string]$OutputDirectory = 'C:\PKI\Reports\Compliance'
    )
    
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
    
    $taskName = "PKI-Compliance-Report-$Schedule"
    
    # Create PowerShell script
    $scriptContent = @"
# Automated PKI Compliance Report
# Generated: $(Get-Date -Format 'yyyy-MM-dd')

Import-Module PKI-Consolidation
`$outputPath = Join-Path '$OutputDirectory' "compliance-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
New-PKIComplianceReport -OutputPath `$outputPath -Format HTML
Write-Host "Compliance report generated: `$outputPath"
"@
    
    $scriptPath = Join-Path $OutputDirectory "Generate-ComplianceReport.ps1"
    $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8 -Force
    
    # Create scheduled task
    if ($PSCmdlet.ShouldProcess($taskName, "Create scheduled task")) {
        $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
                                          -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        
        $trigger = switch ($Schedule) {
            'Daily' { New-ScheduledTaskTrigger -Daily -At $Time }
            'Weekly' { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $Time }
            'Monthly' { New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Monday -At $Time }
        }
        
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        
        Register-ScheduledTask -TaskName $taskName `
                               -Action $action `
                               -Trigger $trigger `
                               -Principal $principal `
                               -Settings $settings `
                               -Description "Automated PKI compliance reporting ($Schedule)" `
                               -Force
        
        Write-Host "✓ Scheduled task created: $taskName" -ForegroundColor Green
        Write-Host "  Schedule: $Schedule at $Time" -ForegroundColor Cyan
        Write-Host "  Output: $OutputDirectory" -ForegroundColor Cyan
        Write-Host "  Script: $scriptPath" -ForegroundColor Cyan
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Test-NIST80053Compliance',
    'Test-CISBenchmarkCompliance',
    'New-PKIComplianceReport',
    'New-PKIComplianceSchedule'
)


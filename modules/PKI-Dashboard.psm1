<#
.SYNOPSIS
    PKI Certificate Lifecycle Dashboard Module

.DESCRIPTION
    Provides real-time monitoring dashboard for PKI health, CA status, and
    certificate lifecycle management with HTML visualization.

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest

#region Dashboard Data Collection

<#
.SYNOPSIS
    Collects comprehensive PKI health data

.DESCRIPTION
    Gathers data from CAs, certificate stores, and OCSP responders

.EXAMPLE
    Get-PKIDashboardData
#>
function Get-PKIDashboardData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$IncludeDetailedMetrics
    )
    
    $data = @{
        Timestamp = Get-Date
        CAs = @()
        Certificates = @{
            Total = 0
            Expiring30Days = 0
            Expiring90Days = 0
            Expired = 0
            ByStore = @{}
        }
        OCSP = @{
            TotalResponders = 0
            Healthy = 0
            Unhealthy = 0
            Responders = @()
        }
        Health = @{
            OverallStatus = 'Unknown'
            Issues = @()
            Warnings = @()
        }
    }
    
    try {
        # Collect CA data
        if (Get-Module -ListAvailable -Name ActiveDirectory) {
            Import-Module ActiveDirectory -ErrorAction SilentlyContinue
            
            try {
                $configNC = (Get-ADRootDSE).ConfigurationNamingContext
                $pkiDN = "CN=Public Key Services,CN=Services,$configNC"
                
                $cas = Get-ADObject -LDAPFilter '(objectClass=pKIEnrollmentService)' `
                                    -SearchBase $pkiDN `
                                    -Properties dNSHostName,certificateTemplates,flags `
                                    -ErrorAction Stop
                
                foreach ($ca in $cas) {
                    $caData = @{
                        Name = $ca.cn
                        Hostname = $ca.dNSHostName
                        IsOnline = $false
                        ResponseTime = $null
                        Templates = $ca.certificateTemplates -join ', '
                    }
                    
                    # Check if CA is online
                    if ($ca.dNSHostName) {
                        try {
                            $ping = Test-Connection $ca.dNSHostName -Count 1 -Quiet -ErrorAction Stop
                            $caData.IsOnline = $ping
                            
                            if ($ping) {
                                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                                $null = Test-Connection $ca.dNSHostName -Count 1 -ErrorAction Stop
                                $sw.Stop()
                                $caData.ResponseTime = $sw.ElapsedMilliseconds
                            }
                        }
                        catch {
                            $caData.IsOnline = $false
                        }
                    }
                    
                    $data.CAs += $caData
                }
            }
            catch {
                $data.Health.Warnings += "Could not retrieve CA list from Active Directory"
            }
        }
        
        # Collect certificate data
        $stores = @('My', 'Root', 'CA')
        foreach ($storeName in $stores) {
            try {
                $store = Get-ChildItem "Cert:\LocalMachine\$storeName" -ErrorAction Stop
                $data.Certificates.ByStore[$storeName] = $store.Count
                $data.Certificates.Total += $store.Count
                
                # Check expiration
                $now = Get-Date
                foreach ($cert in $store) {
                    if ($cert.NotAfter -lt $now) {
                        $data.Certificates.Expired++
                    }
                    elseif ($cert.NotAfter -lt $now.AddDays(30)) {
                        $data.Certificates.Expiring30Days++
                    }
                    elseif ($cert.NotAfter -lt $now.AddDays(90)) {
                        $data.Certificates.Expiring90Days++
                    }
                }
            }
            catch {
                $data.Health.Warnings += "Could not access certificate store: $storeName"
            }
        }
        
        # Collect OCSP data if module available
        if (Get-Command Test-CAOCSPHealth -ErrorAction SilentlyContinue) {
            foreach ($ca in $data.CAs) {
                try {
                    $ocspResult = Test-CAOCSPHealth -CAName $ca.Name -ErrorAction SilentlyContinue
                    if ($ocspResult) {
                        $data.OCSP.TotalResponders += $ocspResult.ResponderCount
                        foreach ($responder in $ocspResult.Responders) {
                            if ($responder.IsReachable) {
                                $data.OCSP.Healthy++
                            }
                            else {
                                $data.OCSP.Unhealthy++
                            }
                            $data.OCSP.Responders += $responder
                        }
                    }
                }
                catch {
                    # Silently continue if OCSP check fails
                }
            }
        }
        
        # Determine overall health
        $healthIssues = 0
        
        if ($data.CAs.Count -eq 0) {
            $data.Health.Issues += "No CAs discovered"
            $healthIssues++
        }
        else {
            $offlineCAs = ($data.CAs | Where-Object { -not $_.IsOnline }).Count
            if ($offlineCAs -gt 0) {
                $data.Health.Issues += "$offlineCAs CA(s) offline"
                $healthIssues++
            }
        }
        
        if ($data.Certificates.Expired -gt 0) {
            $data.Health.Warnings += "$($data.Certificates.Expired) expired certificate(s)"
        }
        
        if ($data.Certificates.Expiring30Days -gt 0) {
            $data.Health.Warnings += "$($data.Certificates.Expiring30Days) certificate(s) expiring in 30 days"
        }
        
        if ($data.OCSP.Unhealthy -gt 0) {
            $data.Health.Issues += "$($data.OCSP.Unhealthy) OCSP responder(s) unhealthy"
            $healthIssues++
        }
        
        # Overall status
        if ($healthIssues -eq 0 -and $data.Health.Warnings.Count -eq 0) {
            $data.Health.OverallStatus = 'Healthy'
        }
        elseif ($healthIssues -eq 0) {
            $data.Health.OverallStatus = 'Warning'
        }
        else {
            $data.Health.OverallStatus = 'Critical'
        }
    }
    catch {
        $data.Health.OverallStatus = 'Error'
        $data.Health.Issues += "Data collection error: $($_.Exception.Message)"
    }
    
    return $data
}

#endregion

#region HTML Dashboard Generation

<#
.SYNOPSIS
    Generates HTML dashboard

.DESCRIPTION
    Creates a beautiful, responsive HTML dashboard with auto-refresh

.PARAMETER OutputPath
    Path to save HTML dashboard

.PARAMETER RefreshSeconds
    Auto-refresh interval in seconds (default: 60)

.PARAMETER Title
    Dashboard title

.EXAMPLE
    New-PKIDashboard -OutputPath 'C:\PKI\dashboard.html' -RefreshSeconds 30
#>
function New-PKIDashboard {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutputPath = (Join-Path $env:TEMP 'pki-dashboard.html'),
        
        [Parameter()]
        [ValidateRange(10, 3600)]
        [int]$RefreshSeconds = 60,
        
        [Parameter()]
        [string]$Title = 'PKI Certificate Lifecycle Dashboard'
    )
    
    Write-Verbose "Collecting dashboard data..."
    $data = Get-PKIDashboardData
    
    Write-Verbose "Generating HTML..."
    
    $statusColor = switch ($data.Health.OverallStatus) {
        'Healthy' { '#107c10' }
        'Warning' { '#ff8c00' }
        'Critical' { '#d13438' }
        default { '#666' }
    }
    
    $statusIcon = switch ($data.Health.OverallStatus) {
        'Healthy' { '✓' }
        'Warning' { '⚠' }
        'Critical' { '✗' }
        default { '?' }
    }
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="$RefreshSeconds">
    <title>$Title</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .header {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
            gap: 15px;
        }
        .status-badge {
            display: inline-block;
            padding: 8px 20px;
            border-radius: 20px;
            color: white;
            font-size: 18px;
            font-weight: bold;
            background: $statusColor;
        }
        .timestamp {
            color: #666;
            font-size: 14px;
            margin-top: 10px;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .card {
            background: white;
            padding: 25px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .card h2 {
            color: #333;
            margin-bottom: 20px;
            font-size: 20px;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        .metric {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid #eee;
        }
        .metric:last-child { border-bottom: none; }
        .metric-label {
            color: #666;
            font-size: 14px;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            color: #333;
        }
        .metric-value.good { color: #107c10; }
        .metric-value.warn { color: #ff8c00; }
        .metric-value.critical { color: #d13438; }
        .ca-list, .ocsp-list, .cert-list {
            list-style: none;
        }
        .ca-item, .ocsp-item, .cert-item {
            padding: 15px;
            margin: 10px 0;
            background: #f9f9f9;
            border-radius: 5px;
            border-left: 4px solid #667eea;
        }
        .ca-item.offline { border-left-color: #d13438; }
        .ca-item.online { border-left-color: #107c10; }
        .ca-name {
            font-weight: bold;
            color: #333;
            margin-bottom: 5px;
        }
        .ca-detail {
            font-size: 12px;
            color: #666;
            margin: 3px 0;
        }
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-indicator.online { background: #107c10; }
        .status-indicator.offline { background: #d13438; }
        .alert {
            padding: 15px;
            margin: 10px 0;
            border-radius: 5px;
            background: #fff3cd;
            border-left: 4px solid #ff8c00;
            color: #856404;
        }
        .alert.critical {
            background: #f8d7da;
            border-left-color: #d13438;
            color: #721c24;
        }
        .footer {
            text-align: center;
            color: white;
            margin-top: 30px;
            padding: 20px;
            background: rgba(255,255,255,0.1);
            border-radius: 10px;
        }
        .refresh-info {
            display: inline-block;
            padding: 5px 15px;
            background: rgba(255,255,255,0.2);
            border-radius: 15px;
            margin-top: 10px;
        }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>
            🔒 $Title
            <span class="status-badge">$statusIcon $($data.Health.OverallStatus.ToUpper())</span>
        </h1>
        <div class="timestamp">
            Last Updated: $($data.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))
            <span style="margin-left: 20px;">Session: $($env:COMPUTERNAME)</span>
        </div>
    </div>
    
    <!-- Metrics Grid -->
    <div class="grid">
        <!-- CA Status -->
        <div class="card">
            <h2>📊 Certificate Authorities</h2>
            <div class="metric">
                <span class="metric-label">Total CAs</span>
                <span class="metric-value">$($data.CAs.Count)</span>
            </div>
            <div class="metric">
                <span class="metric-label">Online</span>
                <span class="metric-value good">$(($data.CAs | Where-Object { $_.IsOnline }).Count)</span>
            </div>
            <div class="metric">
                <span class="metric-label">Offline</span>
                <span class="metric-value $(if (($data.CAs | Where-Object { -not $_.IsOnline }).Count -gt 0) { 'critical' } else { 'good' })">
                    $(($data.CAs | Where-Object { -not $_.IsOnline }).Count)
                </span>
            </div>
        </div>
        
        <!-- Certificate Status -->
        <div class="card">
            <h2>📜 Certificates</h2>
            <div class="metric">
                <span class="metric-label">Total Certificates</span>
                <span class="metric-value">$($data.Certificates.Total)</span>
            </div>
            <div class="metric">
                <span class="metric-label">Expiring (30 days)</span>
                <span class="metric-value $(if ($data.Certificates.Expiring30Days -gt 0) { 'critical' } else { 'good' })">
                    $($data.Certificates.Expiring30Days)
                </span>
            </div>
            <div class="metric">
                <span class="metric-label">Expiring (90 days)</span>
                <span class="metric-value $(if ($data.Certificates.Expiring90Days -gt 0) { 'warn' } else { 'good' })">
                    $($data.Certificates.Expiring90Days)
                </span>
            </div>
            <div class="metric">
                <span class="metric-label">Expired</span>
                <span class="metric-value $(if ($data.Certificates.Expired -gt 0) { 'critical' } else { 'good' })">
                    $($data.Certificates.Expired)
                </span>
            </div>
        </div>
        
        <!-- OCSP Status -->
        <div class="card">
            <h2>🔍 OCSP Responders</h2>
            <div class="metric">
                <span class="metric-label">Total Responders</span>
                <span class="metric-value">$($data.OCSP.TotalResponders)</span>
            </div>
            <div class="metric">
                <span class="metric-label">Healthy</span>
                <span class="metric-value good">$($data.OCSP.Healthy)</span>
            </div>
            <div class="metric">
                <span class="metric-label">Unhealthy</span>
                <span class="metric-value $(if ($data.OCSP.Unhealthy -gt 0) { 'critical' } else { 'good' })">
                    $($data.OCSP.Unhealthy)
                </span>
            </div>
        </div>
    </div>
    
    <!-- Alerts -->
    $(if ($data.Health.Issues.Count -gt 0 -or $data.Health.Warnings.Count -gt 0) { @"
    <div class="card">
        <h2>⚠️ Alerts & Warnings</h2>
        $(foreach ($issue in $data.Health.Issues) { "<div class='alert critical'>🚨 $issue</div>" })
        $(foreach ($warning in $data.Health.Warnings) { "<div class='alert'>⚠️ $warning</div>" })
    </div>
"@ })
    
    <!-- CA Details -->
    $(if ($data.CAs.Count -gt 0) { @"
    <div class="card">
        <h2>🖥️ Certificate Authority Details</h2>
        <ul class="ca-list">
            $(foreach ($ca in $data.CAs) { @"
            <li class="ca-item $(if ($ca.IsOnline) { 'online' } else { 'offline' })">
                <div class="ca-name">
                    <span class="status-indicator $(if ($ca.IsOnline) { 'online' } else { 'offline' })"></span>
                    $($ca.Name)
                </div>
                <div class="ca-detail">Hostname: $($ca.Hostname)</div>
                $(if ($ca.ResponseTime) { "<div class='ca-detail'>Response Time: $($ca.ResponseTime)ms</div>" })
                $(if ($ca.Templates) { "<div class='ca-detail'>Templates: $($ca.Templates)</div>" })
            </li>
"@ })
        </ul>
    </div>
"@ })
    
    <div class="footer">
        <div>PKI-Consolidation Dashboard v1.3.0</div>
        <div>Author: Adrian Johnson &lt;adrian207@gmail.com&gt;</div>
        <div class="refresh-info">⟳ Auto-refresh: Every $RefreshSeconds seconds</div>
    </div>
</div>
</body>
</html>
"@
    
    # Save dashboard
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Verbose "Dashboard saved to: $OutputPath"
    
    return $OutputPath
}

<#
.SYNOPSIS
    Starts the PKI dashboard in browser

.DESCRIPTION
    Generates dashboard and opens in default browser with auto-refresh

.PARAMETER RefreshSeconds
    Auto-refresh interval

.PARAMETER KeepOpen
    Keep PowerShell window open (for continuous generation)

.EXAMPLE
    Start-PKIDashboard

.EXAMPLE
    Start-PKIDashboard -RefreshSeconds 30 -KeepOpen
#>
function Start-PKIDashboard {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$RefreshSeconds = 60,
        
        [Parameter()]
        [switch]$KeepOpen
    )
    
    $dashboardPath = Join-Path $env:TEMP 'pki-dashboard.html'
    
    Write-Host "📊 Starting PKI Dashboard..." -ForegroundColor Cyan
    Write-Host "Dashboard will auto-refresh every $RefreshSeconds seconds" -ForegroundColor Yellow
    
    # Generate initial dashboard
    $path = New-PKIDashboard -OutputPath $dashboardPath -RefreshSeconds $RefreshSeconds
    
    # Open in browser
    Start-Process $path
    
    if ($KeepOpen) {
        Write-Host "`n✓ Dashboard opened in browser" -ForegroundColor Green
        Write-Host "Press Ctrl+C to stop dashboard updates..." -ForegroundColor Yellow
        
        # Keep updating dashboard
        try {
            while ($true) {
                Start-Sleep -Seconds $RefreshSeconds
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Updating dashboard..." -ForegroundColor Cyan
                New-PKIDashboard -OutputPath $dashboardPath -RefreshSeconds $RefreshSeconds | Out-Null
            }
        }
        catch {
            Write-Host "`nDashboard stopped." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "✓ Dashboard opened: $path" -ForegroundColor Green
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Get-PKIDashboardData',
    'New-PKIDashboard',
    'Start-PKIDashboard'
)


# PKI-Consolidation Tool - Operational Guide

**Version:** 1.0  
**Date:** October 18, 2025

---

## Table of Contents

1. [Daily Operations](#1-daily-operations)
2. [Monitoring & Alerting](#2-monitoring--alerting)
3. [Maintenance Procedures](#3-maintenance-procedures)
4. [Troubleshooting](#4-troubleshooting)
5. [Disaster Recovery](#5-disaster-recovery)
6. [Runbooks](#6-runbooks)

---

## 1. Daily Operations

### 1.1 Health Check Routine

**Frequency**: Daily (automated via scheduled task)

```powershell
# Daily CA health check script
function Invoke-DailyPKIHealthCheck {
    $report = @{
        Date = Get-Date
        Checks = @()
    }
    
    # Check 1: CA service status
    $certSvc = Get-Service CertSvc -ErrorAction SilentlyContinue
    $report.Checks += @{
        Name = 'CA Service Status'
        Status = if ($certSvc -and $certSvc.Status -eq 'Running') { 'OK' } else { 'FAIL' }
        Details = if ($certSvc) { $certSvc.Status } else { 'Service not found' }
    }
    
    # Check 2: CRL freshness
    $crlPath = "C:\Windows\System32\CertSrv\CertEnroll\*.crl"
    $latestCRL = Get-ChildItem $crlPath -ErrorAction SilentlyContinue | 
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $crlAge = if ($latestCRL) { (Get-Date) - $latestCRL.LastWriteTime } else { $null }
    
    $report.Checks += @{
        Name = 'CRL Freshness'
        Status = if ($crlAge -and $crlAge.TotalHours -lt 24) { 'OK' } elseif ($crlAge) { 'WARN' } else { 'FAIL' }
        Details = if ($crlAge) { "Last updated: $([math]::Round($crlAge.TotalHours, 1)) hours ago" } else { 'No CRL found' }
    }
    
    # Check 3: OCSP responder (if applicable)
    $ocspSvc = Get-Service OCSPSvc -ErrorAction SilentlyContinue
    if ($ocspSvc) {
        $report.Checks += @{
            Name = 'OCSP Service Status'
            Status = if ($ocspSvc.Status -eq 'Running') { 'OK' } else { 'WARN' }
            Details = $ocspSvc.Status
        }
    }
    
    # Check 4: Certificate issuance (last 24h)
    $yesterday = (Get-Date).AddDays(-1)
    $recentIssuance = Get-EventLog -LogName Application -Source CertificationAuthority -After $yesterday -ErrorAction SilentlyContinue |
        Where-Object { $_.EventID -eq 58 } | Measure-Object
    
    $report.Checks += @{
        Name = 'Certificate Issuance (24h)'
        Status = if ($recentIssuance.Count -gt 0) { 'OK' } else { 'WARN' }
        Details = "$($recentIssuance.Count) certificates issued"
    }
    
    # Check 5: Disk space
    $drive = (Get-Item $env:SystemDrive).PSDrive
    $freeGB = (Get-PSDrive $drive.Name).Free / 1GB
    
    $report.Checks += @{
        Name = 'Disk Space'
        Status = if ($freeGB -gt 10) { 'OK' } elseif ($freeGB -gt 5) { 'WARN' } else { 'FAIL' }
        Details = "$([math]::Round($freeGB, 2)) GB free"
    }
    
    # Generate report
    $report.Checks | Format-Table Name, Status, Details -AutoSize
    
    # Send alert if any failures
    $failures = $report.Checks | Where-Object { $_.Status -eq 'FAIL' }
    if ($failures) {
        Send-MailMessage -To 'pki-team@contoso.com' `
            -From 'pki-monitor@contoso.com' `
            -Subject "[ALERT] PKI Health Check Failures" `
            -Body ($failures | ConvertTo-Html | Out-String) `
            -SmtpServer 'smtp.contoso.com'
    }
    
    # Log to file
    $reportFile = "C:\PKI\Consolidation\reports\health-check-$(Get-Date -Format 'yyyyMMdd').json"
    $report | ConvertTo-Json -Depth 10 | Out-File $reportFile
}

# Schedule as daily task
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-File C:\PKI\Scripts\Daily-HealthCheck.ps1'
$trigger = New-ScheduledTaskTrigger -Daily -At 6am
Register-ScheduledTask -TaskName 'PKI-Daily-HealthCheck' -Action $action -Trigger $trigger -RunLevel Highest
```

### 1.2 Log Review

**Frequency**: Daily

```powershell
# Review yesterday's logs for errors/warnings
$yesterday = (Get-Date).AddDays(-1).Date
$logs = Get-Content C:\PKI\Consolidation\PKI-Consolidation.log | ForEach-Object {
    if ($_ -match '^(\d{4}-\d{2}-\d{2}).*\[(ERROR|WARN)\](.*)$') {
        [PSCustomObject]@{
            Date = [DateTime]::Parse($Matches[1])
            Level = $Matches[2]
            Message = $Matches[3].Trim()
        }
    }
} | Where-Object { $_.Date -ge $yesterday }

if ($logs) {
    Write-Host "⚠️  Errors/Warnings found in last 24 hours:" -ForegroundColor Yellow
    $logs | Format-Table Date, Level, Message -AutoSize
} else {
    Write-Host "✅ No errors/warnings in last 24 hours" -ForegroundColor Green
}
```

### 1.3 Certificate Expiration Monitoring

**Frequency**: Weekly

```powershell
# Check for expiring certificates
function Get-ExpiringCertificates {
    param([int]$DaysThreshold = 30)
    
    $expiringSoon = @()
    $threshold = (Get-Date).AddDays($DaysThreshold)
    
    # Check CA certificates
    $caStore = Get-ChildItem Cert:\LocalMachine\CA -ErrorAction SilentlyContinue
    foreach ($cert in $caStore) {
        if ($cert.NotAfter -lt $threshold) {
            $expiringSoon += [PSCustomObject]@{
                Store = 'CA'
                Subject = $cert.Subject
                Thumbprint = $cert.Thumbprint
                Expires = $cert.NotAfter
                DaysUntilExpiry = [Math]::Round(($cert.NotAfter - (Get-Date)).TotalDays, 0)
            }
        }
    }
    
    # Check root certificates
    $rootStore = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue
    foreach ($cert in $rootStore) {
        if ($cert.NotAfter -lt $threshold) {
            $expiringSoon += [PSCustomObject]@{
                Store = 'Root'
                Subject = $cert.Subject
                Thumbprint = $cert.Thumbprint
                Expires = $cert.NotAfter
                DaysUntilExpiry = [Math]::Round(($cert.NotAfter - (Get-Date)).TotalDays, 0)
            }
        }
    }
    
    $expiringSoon | Sort-Object DaysUntilExpiry
}

# Execute and alert
$expiring = Get-ExpiringCertificates -DaysThreshold 90
if ($expiring) {
    Write-Host "⚠️  Certificates expiring within 90 days:" -ForegroundColor Yellow
    $expiring | Format-Table Store, Subject, Expires, DaysUntilExpiry -AutoSize
    
    # Send alert email
    $body = $expiring | ConvertTo-Html -Property Store, Subject, Expires, DaysUntilExpiry | Out-String
    Send-MailMessage -To 'pki-team@contoso.com' `
        -From 'pki-monitor@contoso.com' `
        -Subject "[ALERT] Certificates Expiring Soon" `
        -Body $body -BodyAsHtml `
        -SmtpServer 'smtp.contoso.com'
}
```

---

## 2. Monitoring & Alerting

### 2.1 Key Performance Indicators (KPIs)

| KPI | Target | Alert Threshold | Check Frequency |
|-----|--------|-----------------|-----------------|
| CA Service Uptime | 99.9% | < 99.5% | Continuous |
| Certificate Issuance Latency | < 5 sec | > 10 sec | Per-request |
| CRL Freshness | < 24 hours | > 36 hours | Hourly |
| OCSP Response Time | < 2 sec | > 5 sec | Every 15 min |
| Failed Issuance Rate | < 1% | > 5% | Daily |
| Disk Space Free | > 20 GB | < 10 GB | Daily |

### 2.2 Event Log Monitoring

**Critical Events to Monitor**:

```powershell
# Configure event log forwarding to SIEM
$events = @(
    @{ LogName='Application'; Source='CertificationAuthority'; EventID=48 },  # CA service started
    @{ LogName='Application'; Source='CertificationAuthority'; EventID=49 },  # CA service stopped
    @{ LogName='Application'; Source='CertificationAuthority'; EventID=100 }, # Certificate issuance failed
    @{ LogName='System'; Source='Service Control Manager'; EventID=7036 }      # CertSvc state change
)

foreach ($evt in $events) {
    $query = @"
    <QueryList>
      <Query Id="0">
        <Select Path="$($evt.LogName)">
          *[System[Provider[@Name='$($evt.Source)'] and (EventID=$($evt.EventID))]]
        </Select>
      </Query>
    </QueryList>
"@
    
    # Forward to SIEM
    $subscription = Register-WmiEvent -Query "SELECT * FROM __InstanceCreationEvent WITHIN 10 WHERE TargetInstance ISA 'Win32_NTLogEvent' AND TargetInstance.Logfile='$($evt.LogName)' AND TargetInstance.SourceName='$($evt.Source)' AND TargetInstance.EventCode=$($evt.EventID)" `
        -Action {
            # Send to SIEM
            $payload = @{
                timestamp = (Get-Date).ToString('o')
                source = $Event.SourceEventArgs.NewEvent.TargetInstance.SourceName
                eventid = $Event.SourceEventArgs.NewEvent.TargetInstance.EventCode
                message = $Event.SourceEventArgs.NewEvent.TargetInstance.Message
            } | ConvertTo-Json
            
            Invoke-RestMethod -Uri 'https://siem.contoso.com/collector' -Method Post -Body $payload -ContentType 'application/json'
        }
}
```

### 2.3 Performance Counters

```powershell
# Collect PKI performance metrics
function Get-PKIPerformanceMetrics {
    $metrics = @{}
    
    # Certificate Services performance counters
    $counters = @(
        '\Certification Authority\Request processing time (ms)',
        '\Certification Authority\Requests/sec',
        '\Certification Authority\Failed Requests/sec',
        '\Certification Authority\Pending Requests'
    )
    
    foreach ($counter in $counters) {
        try {
            $value = (Get-Counter -Counter $counter -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
            $name = $counter -replace '\\Certification Authority\\', ''
            $metrics[$name] = $value
        } catch {
            Write-Warning "Counter not available: $counter"
        }
    }
    
    $metrics
}

# Display metrics
Get-PKIPerformanceMetrics | Format-Table -AutoSize
```

---

## 3. Maintenance Procedures

### 3.1 Weekly Maintenance

**Tasks**:
1. Review health check reports
2. Check certificate expiration dashboard
3. Verify backup completion
4. Review audit logs for anomalies
5. Check disk space and cleanup old files

```powershell
# Weekly cleanup script
function Invoke-WeeklyMaintenance {
    Write-Host "=== Weekly PKI Maintenance ===" -ForegroundColor Cyan
    
    # 1. Cleanup old work files (> 90 days)
    $cutoff = (Get-Date).AddDays(-90)
    $oldFiles = Get-ChildItem C:\PKI\Consolidation\work -Recurse | Where-Object { $_.LastWriteTime -lt $cutoff }
    
    if ($oldFiles) {
        Write-Host "Removing $($oldFiles.Count) old work files..."
        $oldFiles | Remove-Item -Force -Confirm:$false
    }
    
    # 2. Archive old logs
    $logCutoff = (Get-Date).AddDays(-30)
    $archiveDir = "C:\PKI\Consolidation\archives\$(Get-Date -Format 'yyyyMM')"
    New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
    
    Get-ChildItem C:\PKI\Consolidation\reports\*.csv | Where-Object { $_.LastWriteTime -lt $logCutoff } | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $archiveDir -Force
    }
    
    # 3. Verify backups
    $latestBackup = Get-ChildItem C:\PKI\Consolidation\backups -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1
    if ($latestBackup) {
        $backupAge = (Get-Date) - $latestBackup.CreationTime
        if ($backupAge.TotalDays -gt 7) {
            Write-Host "⚠️  Latest backup is $([Math]::Round($backupAge.TotalDays, 0)) days old!" -ForegroundColor Yellow
        } else {
            Write-Host "✅ Backup status: OK (last backup $([Math]::Round($backupAge.TotalDays, 1)) days ago)" -ForegroundColor Green
        }
    }
    
    # 4. Check CRL distribution
    $testURL = 'http://pki.contoso.com/crl/ContosoRootCA.crl'
    try {
        $response = Invoke-WebRequest -Uri $testURL -UseBasicParsing -TimeoutSec 5
        Write-Host "✅ CRL distribution point accessible" -ForegroundColor Green
    } catch {
        Write-Host "❌ CRL distribution point FAILED: $testURL" -ForegroundColor Red
    }
    
    Write-Host "`nWeekly maintenance complete." -ForegroundColor Cyan
}

# Schedule as weekly task (Sundays at 3am)
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-File C:\PKI\Scripts\Weekly-Maintenance.ps1'
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
Register-ScheduledTask -TaskName 'PKI-Weekly-Maintenance' -Action $action -Trigger $trigger -RunLevel Highest
```

### 3.2 Monthly Maintenance

**Tasks**:
1. Review security audit logs
2. Rotate service account passwords
3. Test disaster recovery procedures
4. Update documentation
5. Review and renew expiring certificates

### 3.3 Quarterly Maintenance

**Tasks**:
1. Full security audit
2. Performance capacity review
3. Update threat model
4. Review SLAs and KPIs
5. Training/knowledge transfer for team

---

## 4. Troubleshooting

### 4.1 CA Service Won't Start

**Symptoms**: CertSvc service fails to start after configuration change

**Diagnosis**:

```powershell
# Check event logs
Get-EventLog -LogName Application -Source CertificationAuthority -Newest 10

# Check registry permissions
$caRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
Get-Acl $caRegPath | Format-List

# Verify database integrity
certutil -dbstatus
```

**Resolution**:

```powershell
# 1. Restore registry backup
Stop-Service CertSvc -Force -ErrorAction SilentlyContinue
$backup = Get-ChildItem C:\PKI\Consolidation\work\*-backup.reg | Sort-Object LastWriteTime -Descending | Select-Object -First 1
reg import $backup.FullName /y

# 2. Repair database (if corrupted)
esentutl /g "C:\Windows\System32\CertLog\CA.edb"
esentutl /p "C:\Windows\System32\CertLog\CA.edb"

# 3. Restart service
Start-Service CertSvc

# 4. Verify health
certutil -ping
```

### 4.2 Certificate Issuance Failures

**Symptoms**: Clients unable to request certificates

**Diagnosis**:

```powershell
# Check pending requests
certutil -view -restrict "Disposition=9" -out "RequestID,RequesterName,NotBefore,NotAfter"

# Check templates
certutil -template

# Test manual issuance
certutil -submit C:\path\to\request.req
```

**Resolution**:

```powershell
# 1. Verify template permissions
$template = Get-CATemplate -Name "YourTemplate"
$template | Select-Object Name, SecurityDescriptor

# 2. Re-publish templates
certutil -SetCATemplates +YourTemplate

# 3. Restart CA service
Restart-Service CertSvc
```

### 4.3 CRL Publication Failures

**Symptoms**: CRLs not updating or not accessible

**Diagnosis**:

```powershell
# Check CRL generation
certutil -CRL

# Verify CRL files
Get-ChildItem C:\Windows\System32\CertSrv\CertEnroll\*.crl | Select-Object Name, LastWriteTime

# Test CRL retrieval
certutil -verify -urlfetch C:\path\to\cert.cer
```

**Resolution**:

```powershell
# 1. Manually generate CRL
certutil -CRL

# 2. Re-publish to AD
$crl = Get-ChildItem C:\Windows\System32\CertSrv\CertEnroll\*.crl | Sort-Object LastWriteTime -Descending | Select-Object -First 1
certutil -dspublish -f $crl.FullName

# 3. Copy to web server
Copy-Item $crl.FullName -Destination \\webserver\c$\inetpub\wwwroot\pki\crl\

# 4. Verify HTTP access
Invoke-WebRequest -Uri 'http://pki.contoso.com/crl/CA.crl' -UseBasicParsing
```

---

## 5. Disaster Recovery

### 5.1 CA Server Failure

**Recovery Time Objective (RTO)**: 4 hours  
**Recovery Point Objective (RPO)**: 24 hours

**Procedure**:

1. **Deploy new CA server**:
   ```powershell
   # Install AD CS role
   Install-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools
   ```

2. **Restore CA database**:
   ```powershell
   # Restore from backup
   $latestBackup = Get-ChildItem C:\Backups\CADatabase | Sort-Object CreationTime -Descending | Select-Object -First 1
   certutil -restoredb $latestBackup.FullName
   ```

3. **Restore CA private key**:
   ```powershell
   # Import from PFX backup
   $pfxPath = "C:\Backups\CA-PrivateKey.pfx"
   $password = Get-Content "C:\Backups\CA-PrivateKey.pfx.password" | ConvertTo-SecureString
   Import-PfxCertificate -FilePath $pfxPath -CertStoreLocation Cert:\LocalMachine\My -Password $password
   ```

4. **Restore registry configuration**:
   ```powershell
   $regBackup = Get-ChildItem C:\Backups\Registry\*.reg | Sort-Object CreationTime -Descending | Select-Object -First 1
   reg import $regBackup.FullName /y
   ```

5. **Start CA service**:
   ```powershell
   Start-Service CertSvc
   certutil -ping
   ```

6. **Verify operation**:
   ```powershell
   # Test certificate issuance
   certreq -submit C:\Test\request.req C:\Test\issued.cer
   
   # Verify CRL
   certutil -CRL
   ```

### 5.2 Active Directory Corruption

**Symptoms**: CA objects missing from AD

**Recovery**:

```powershell
# Re-publish all CA certificates to AD
$rootCer = Get-ChildItem C:\PKI\Consolidation\exports\*RootCA*.cer | Select-Object -First 1
certutil -dspublish -f $rootCer.FullName RootCA

Get-ChildItem C:\PKI\Consolidation\work\issued\*.cer | ForEach-Object {
    certutil -dspublish -f $_.FullName SubCA
}

# Verify publication
certutil -viewstore "ldap:///CN=Certification Authorities,CN=Public Key Services,CN=Services,CN=Configuration,DC=contoso,DC=com?cACertificate"
```

### 5.3 Complete Environment Rebuild

See [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) for full rebuild procedures.

---

## 6. Runbooks

### 6.1 Certificate Renewal Runbook

**Trigger**: CA certificate expiring within 90 days

**Steps**:

1. Generate renewal request:
   ```powershell
   certutil -renewCert ReuseKeys
   ```

2. Submit to parent CA or self-sign (if root)

3. Install renewed certificate:
   ```powershell
   certutil -installCert C:\Renewed\ca-cert.cer
   ```

4. Publish to AD:
   ```powershell
   certutil -dspublish -f C:\Renewed\ca-cert.cer SubCA
   ```

5. Restart CA service:
   ```powershell
   Restart-Service CertSvc
   ```

6. Notify clients (if root CA)

### 6.2 Emergency CA Shutdown Runbook

**Trigger**: CA compromise suspected

**Steps**:

1. **Immediately stop service**:
   ```powershell
   Stop-Service CertSvc -Force
   Disable-Service CertSvc
   ```

2. **Isolate server**:
   ```powershell
   Disable-NetAdapter -Name * -Confirm:$false
   ```

3. **Revoke all issued certificates** (if necessary):
   ```powershell
   # From offline console
   certutil -revoke <serial> <reason-code>
   certutil -CRL
   ```

4. **Notify incident response team**

5. **Preserve forensic evidence**

6. **Document timeline**

### 6.3 Template Deployment Runbook

**Trigger**: New certificate template needed

**Steps**:

1. Create template in AD:
   ```powershell
   # Via Certificate Templates MMC snap-in
   certtmpl.msc
   ```

2. Publish to CA:
   ```powershell
   certutil -SetCATemplates +NewTemplateName
   ```

3. Set permissions:
   ```powershell
   # Via Certificate Templates MMC or PowerShell
   ```

4. Test issuance:
   ```powershell
   # Via Certificates MMC or certreq
   ```

5. Deploy via GPO (auto-enrollment)

---

## Appendix: Contact Information

| Role | Contact | Phone | Email |
|------|---------|-------|-------|
| **PKI Team Lead** | John Doe | +1-555-0100 | john.doe@contoso.com |
| **On-Call Engineer** | 24/7 Rotation | +1-555-0911 | pki-oncall@contoso.com |
| **Security Team** | Jane Smith | +1-555-0200 | security@contoso.com |
| **Infrastructure Team** | Bob Johnson | +1-555-0300 | infra@contoso.com |

**Escalation Path**:
1. On-Call Engineer (0-30 min)
2. PKI Team Lead (30-60 min)
3. Infrastructure Manager (60-120 min)
4. CIO (> 2 hours or business-critical)

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-18  
**Next Review**: 2026-01-18


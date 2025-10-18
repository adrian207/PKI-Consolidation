# PKI-Consolidation Tool - Security Hardening Guide

**Version:** 1.0  
**Date:** October 18, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Status:** Production  
**Classification:** Public

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Credential Management](#2-credential-management)
3. [Access Controls](#3-access-controls)
4. [Audit & Logging](#4-audit--logging)
5. [Network Security](#5-network-security)
6. [Code Security](#6-code-security)
7. [Operational Security](#7-operational-security)
8. [Compliance Checklist](#8-compliance-checklist)

---

## 1. Executive Summary

### 1.1 Purpose

This document provides security hardening guidance for the PKI-Consolidation Tool to mitigate identified risks and ensure compliance with organizational security policies.

### 1.2 Threat Summary

| Threat ID | Threat | Current Risk | Target Risk | Priority |
|-----------|--------|--------------|-------------|----------|
| **T1** | Credential Exposure | **HIGH** | LOW | P0 |
| **T2** | Unauthorized Registry Modification | **HIGH** | LOW | P0 |
| **T3** | Privilege Escalation | MEDIUM | LOW | P1 |
| **T4** | Audit Trail Tampering | MEDIUM | LOW | P1 |
| **T5** | Denial of Service | MEDIUM | LOW | P2 |

### 1.3 Implementation Priority

**Phase 1** (Immediate - Before Production Use):
- Implement secure credential storage (T1)
- Add privilege validation (T3)
- Harden file permissions (T4)

**Phase 2** (Within 30 days):
- Implement log integrity protection (T4)
- Add input validation and sanitization (T2)
- Network segmentation verification (T5)

**Phase 3** (Within 90 days):
- Implement code signing
- Add SIEM integration
- Conduct penetration testing

---

## 2. Credential Management

### 2.1 Problem Statement

**Current Implementation** (INSECURE):
```powershell
# Lines 60-62 in PKI-Consolidation.ps1
$Global:VaultName = ''
$Global:KeyfactorBaseUrl = ''
$Global:KeyfactorApiKey = ''  # <-- Plaintext credential storage
```

**Risks**:
- Credentials visible in script source
- Exposed in memory dumps
- Logged in error messages
- Visible in process listings
- No rotation capability

### 2.2 Secure Credential Storage Options

#### Option A: Windows Credential Manager (Recommended for On-Premises)

**Implementation**:

```powershell
# 1. Store credentials securely (one-time setup)
function Set-PKICredential {
    param(
        [string]$Target,
        [string]$Username = 'PKI-Tool',
        [SecureString]$Password
    )
    
    $credPath = "PKI-Consolidation:$Target"
    
    # Create credential object
    $cred = New-Object System.Management.Automation.PSCredential($Username, $Password)
    
    # Store in Windows Credential Manager (requires CredentialManager module)
    if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
        Install-Module CredentialManager -Force -Scope CurrentUser
    }
    Import-Module CredentialManager
    
    New-StoredCredential -Target $credPath -UserName $cred.UserName -Password ($cred.GetNetworkCredential().Password) -Persist LocalMachine
    
    Write-Host "[OK] Credential stored securely: $credPath" -ForegroundColor Green
}

# Store Keyfactor API key
$apiKey = Read-Host -Prompt "Enter Keyfactor API Key" -AsSecureString
Set-PKICredential -Target "KeyfactorAPIKey" -Password $apiKey

# 2. Retrieve credentials in script
function Get-PKICredential {
    param([string]$Target)
    
    $credPath = "PKI-Consolidation:$Target"
    
    if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
        throw "CredentialManager module not installed. Run: Install-Module CredentialManager"
    }
    Import-Module CredentialManager
    
    $cred = Get-StoredCredential -Target $credPath
    if (-not $cred) {
        throw "Credential not found: $credPath. Run Set-PKICredential first."
    }
    
    return $cred
}

# 3. Use in script (replace lines 60-62)
$Global:VaultName = 'contoso-pki-vault'
$Global:KeyfactorBaseUrl = 'https://keyfactor.contoso.com'

# Retrieve API key securely
try {
    $keyfactorCred = Get-PKICredential -Target "KeyfactorAPIKey"
    $Global:KeyfactorApiKey = $keyfactorCred.GetNetworkCredential().Password
} catch {
    Write-Log "Keyfactor credentials not configured. Cloud features disabled." 'WARN'
    $Global:KeyfactorApiKey = $null
}
```

**Deployment**:
```powershell
# One-time credential setup (run as admin)
.\Setup-PKICredentials.ps1

# Script automatically retrieves credentials at runtime
.\PKI-Consolidation.ps1
```

#### Option B: Azure Key Vault (Recommended for Cloud/Hybrid)

**Implementation**:

```powershell
# 1. Create Key Vault secrets
az keyvault secret set --vault-name contoso-pki-vault --name KeyfactorAPIKey --value "<your-api-key>"

# 2. Grant managed identity or service principal access
$spnObjectId = (az ad sp show --id <app-id> --query objectId -o tsv)
az keyvault set-policy --name contoso-pki-vault --object-id $spnObjectId --secret-permissions get list

# 3. Retrieve in script
function Get-AzureKeyVaultSecret {
    param([string]$VaultName, [string]$SecretName)
    
    # Ensure Azure CLI is authenticated
    $accountCheck = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Azure CLI not authenticated. Run 'az login'" 'ERROR'
        throw "Azure authentication required"
    }
    
    $secret = az keyvault secret show --vault-name $VaultName --name $SecretName --query value -o tsv 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve secret '$SecretName' from vault '$VaultName': $secret"
    }
    
    return $secret
}

# 4. Use in script
$Global:VaultName = 'contoso-pki-vault'
$Global:KeyfactorBaseUrl = 'https://keyfactor.contoso.com'

try {
    $Global:KeyfactorApiKey = Get-AzureKeyVaultSecret -VaultName $Global:VaultName -SecretName 'KeyfactorAPIKey'
} catch {
    Write-Log "Failed to retrieve Keyfactor API key from AKV: $($_.Exception.Message)" 'ERROR'
    $Global:KeyfactorApiKey = $null
}
```

#### Option C: CyberArk / HashiCorp Vault (Enterprise)

**Implementation**:

```powershell
# CyberArk AIM
function Get-CyberArkPassword {
    param(
        [string]$AppID,
        [string]$Safe,
        [string]$Object,
        [string]$AIMServer
    )
    
    $uri = "https://$AIMServer/AIMWebService/api/Accounts?AppID=$AppID&Safe=$Safe&Object=$Object"
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -UseDefaultCredentials
        return $response.Content
    } catch {
        throw "CyberArk password retrieval failed: $($_.Exception.Message)"
    }
}

# HashiCorp Vault
function Get-VaultSecret {
    param(
        [string]$VaultAddr,
        [string]$VaultToken,
        [string]$SecretPath
    )
    
    $headers = @{ 'X-Vault-Token' = $VaultToken }
    $uri = "$VaultAddr/v1/$SecretPath"
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        return $response.data.value
    } catch {
        throw "Vault secret retrieval failed: $($_.Exception.Message)"
    }
}
```

### 2.3 Credential Rotation

```powershell
# Automated credential rotation script
function Update-PKICredential {
    param(
        [string]$Target,
        [SecureString]$NewPassword
    )
    
    # Update in Windows Credential Manager
    $credPath = "PKI-Consolidation:$Target"
    Remove-StoredCredential -Target $credPath -ErrorAction SilentlyContinue
    New-StoredCredential -Target $credPath -UserName 'PKI-Tool' -Password (ConvertFrom-SecureString $NewPassword -AsPlainText) -Persist LocalMachine
    
    Write-Log "Credential rotated: $Target"
}

# Schedule rotation (e.g., every 90 days)
# Task Scheduler: Run Update-PKICredential script on schedule
```

---

## 3. Access Controls

### 3.1 Privilege Validation

**Add to Bootstrap Section** (after line 80):

```powershell
function Test-RequiredPrivileges {
    [CmdletBinding()]
    param()
    
    Write-Log "Validating execution privileges..."
    
    # Test 1: Local Administrator
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        throw "This script requires local administrator privileges. Please run as administrator."
    }
    Write-Log "✓ Local Administrator: Confirmed"
    
    # Test 2: Enterprise Admin (for AD operations)
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $configNC = (Get-ADRootDSE).ConfigurationNamingContext
        $domain = $configNC -replace '^.*?DC=','' -replace ',DC=','.'
        $enterpriseAdmins = Get-ADGroup "Enterprise Admins" -Server $domain -ErrorAction Stop
        $isMember = (Get-ADGroupMember $enterpriseAdmins -Recursive | Where-Object { $_.SID -eq $identity.User }) -ne $null
        
        if ($isMember) {
            Write-Log "✓ Enterprise Admin: Confirmed"
        } else {
            Write-Log "⚠ Not an Enterprise Admin. AD publication operations may fail." 'WARN'
        }
    } catch {
        Write-Log "⚠ Could not verify Enterprise Admin membership: $($_.Exception.Message)" 'WARN'
    }
    
    # Test 3: CA Administrator (if CertSvc exists)
    $certSvc = Get-Service CertSvc -ErrorAction SilentlyContinue
    if ($certSvc) {
        try {
            $ping = & certutil -ping 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "✓ CA Administrator: Confirmed (certutil -ping succeeded)"
            } else {
                Write-Log "⚠ CA service not responding or insufficient CA permissions" 'WARN'
            }
        } catch {
            Write-Log "⚠ Could not verify CA administrator access: $($_.Exception.Message)" 'WARN'
        }
    }
    
    # Test 4: Registry write access
    $testKey = "HKLM:\SOFTWARE\PKI-Consolidation-Test"
    try {
        New-Item -Path $testKey -Force | Out-Null
        Remove-Item -Path $testKey -Force
        Write-Log "✓ Registry Write Access: Confirmed"
    } catch {
        throw "Registry write access denied. Cannot proceed."
    }
    
    Write-Log "Privilege validation complete."
}

# Execute privilege checks
Test-RequiredPrivileges
```

### 3.2 File System Permissions

**Add to Bootstrap Section** (after directory creation):

```powershell
function Set-SecureDirectoryPermissions {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "Directory not found: $Path"
    }
    
    Write-Log "Hardening permissions on: $Path"
    
    # Get current ACL
    $acl = Get-Acl $Path
    
    # Disable inheritance
    $acl.SetAccessRuleProtection($true, $false)
    
    # Remove all existing rules
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
    
    # Grant SYSTEM full control
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'NT AUTHORITY\SYSTEM',
        'FullControl',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow'
    )
    $acl.SetAccessRule($systemRule)
    
    # Grant Administrators full control
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators',
        'FullControl',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow'
    )
    $acl.SetAccessRule($adminRule)
    
    # Apply ACL
    Set-Acl -Path $Path -AclObject $acl
    
    Write-Log "Permissions hardened: $Path (SYSTEM + Administrators only)"
}

# Harden sensitive directories
$sensitiveDirs = @(
    "$OutDir\config",
    "$OutDir\work",
    "$OutDir\exports"
)

foreach ($dir in $sensitiveDirs) {
    if (Test-Path $dir) {
        Set-SecureDirectoryPermissions -Path $dir
    }
}

# Harden log file
if (Test-Path $Global:LogPath) {
    $logAcl = Get-Acl $Global:LogPath
    $logAcl.SetAccessRuleProtection($true, $false)
    
    # SYSTEM: Full Control
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'NT AUTHORITY\SYSTEM', 'FullControl', 'Allow'
    )
    $logAcl.SetAccessRule($systemRule)
    
    # Administrators: Read + Append
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators', 'Read,AppendData', 'Allow'
    )
    $logAcl.SetAccessRule($adminRule)
    
    Set-Acl -Path $Global:LogPath -AclObject $logAcl
    Write-Log "Log file permissions hardened (SYSTEM: Full, Admins: Read+Append)"
}
```

### 3.3 Just-In-Time Administration

**Implement Privileged Access Workstation (PAW)**:

1. **Dedicated Admin Workstation**: Run script only from hardened admin workstation
2. **Time-Limited Elevation**: Request temporary Enterprise Admin access via PAM solution
3. **Session Recording**: Enable PowerShell transcription for audit

```powershell
# Enable PowerShell transcription (add to Bootstrap)
$transcriptDir = Join-Path $OutDir 'transcripts'
if (-not (Test-Path $transcriptDir)) {
    New-Item -Path $transcriptDir -ItemType Directory -Force | Out-Null
    Set-SecureDirectoryPermissions -Path $transcriptDir
}

$transcriptFile = Join-Path $transcriptDir "PKI-Session-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$env:USERNAME.txt"
Start-Transcript -Path $transcriptFile -Append

Write-Log "PowerShell transcript started: $transcriptFile"
```

---

## 4. Audit & Logging

### 4.1 Enhanced Logging with Integrity Protection

**Replace Write-Log function** (lines 82-87):

```powershell
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Msg,
        
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO',
        
        [string]$SessionID = $Global:SessionID,
        [string]$User = $env:USERNAME,
        [string]$Component = 'Main'
    )
    
    # Generate structured log entry
    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'
    $computerName = $env:COMPUTERNAME
    
    # Structured log format (JSON for SIEM compatibility)
    $logEntry = @{
        Timestamp = $timestamp
        Level = $Level
        SessionID = $SessionID
        User = $User
        Computer = $computerName
        Component = $Component
        Message = $Msg
        ProcessID = $PID
    }
    
    $logLine = $logEntry | ConvertTo-Json -Compress
    
    # Calculate HMAC for integrity (if key available)
    if ($Global:LogHMACKey) {
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Global:LogHMACKey)
        $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($logLine))
        $hashString = [BitConverter]::ToString($hashBytes) -replace '-',''
        $logLine = "$logLine|HMAC:$hashString"
    }
    
    # Console output (structured for readability)
    if ($Global:EnableVerboseLog) {
        $color = switch ($Level) {
            'ERROR' { 'Red' }
            'WARN'  { 'Yellow' }
            'DEBUG' { 'Gray' }
            default { 'White' }
        }
        Write-Host "[$timestamp] [$Level] $Msg" -ForegroundColor $color
    }
    
    # File output
    try {
        Add-Content -Path $Global:LogPath -Value $logLine -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
    
    # Event log output (for critical events)
    if ($Level -eq 'ERROR') {
        try {
            Write-EventLog -LogName Application -Source 'PKI-Consolidation' -EventId 1001 -EntryType Error -Message $Msg -ErrorAction SilentlyContinue
        } catch {
            # Event log source may not exist; create it
            New-EventLog -LogName Application -Source 'PKI-Consolidation' -ErrorAction SilentlyContinue
        }
    }
}

# Initialize session
$Global:SessionID = [Guid]::NewGuid().ToString()
Write-Log "PKI-Consolidation session started" 'INFO'

# Load HMAC key from secure storage
try {
    $Global:LogHMACKey = Get-PKICredential -Target "LogHMACKey" -ErrorAction Stop
    Write-Log "Log integrity protection enabled" 'INFO'
} catch {
    Write-Warning "Log HMAC key not configured. Integrity protection disabled."
    $Global:LogHMACKey = $null
}
```

**Setup HMAC Key** (one-time):

```powershell
# Generate and store HMAC key
$hmacKey = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
$secureKey = ConvertTo-SecureString $hmacKey -AsPlainText -Force
Set-PKICredential -Target "LogHMACKey" -Password $secureKey

Write-Host "[OK] Log HMAC key generated and stored securely" -ForegroundColor Green
```

### 4.2 Log Verification

```powershell
function Test-LogIntegrity {
    param([string]$LogPath = $Global:LogPath)
    
    Write-Host "Verifying log integrity..." -ForegroundColor Cyan
    
    try {
        $logHMACKey = (Get-PKICredential -Target "LogHMACKey").GetNetworkCredential().Password
    } catch {
        Write-Host "[ERROR] Cannot verify logs: HMAC key not available" -ForegroundColor Red
        return $false
    }
    
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($logHMACKey)
    
    $lines = Get-Content $LogPath
    $tamperedCount = 0
    
    foreach ($line in $lines) {
        if ($line -match '(.*)\|HMAC:(.+)$') {
            $content = $Matches[1]
            $storedHash = $Matches[2]
            
            $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($content))
            $computedHash = [BitConverter]::ToString($hashBytes) -replace '-',''
            
            if ($computedHash -ne $storedHash) {
                Write-Host "[WARN] Tampered entry detected: $($content.Substring(0, [Math]::Min(100, $content.Length)))..." -ForegroundColor Yellow
                $tamperedCount++
            }
        }
    }
    
    if ($tamperedCount -eq 0) {
        Write-Host "[OK] Log integrity verified. No tampering detected." -ForegroundColor Green
        return $true
    } else {
        Write-Host "[ERROR] $tamperedCount tampered log entries detected!" -ForegroundColor Red
        return $false
    }
}

# Usage
Test-LogIntegrity
```

### 4.3 SIEM Integration

**Forward logs to SIEM (Splunk, Sentinel, etc.)**:

```powershell
function Send-ToSIEM {
    param(
        [string]$Message,
        [string]$Level,
        [string]$SIEMEndpoint = 'https://siem.contoso.com/collector'
    )
    
    $payload = @{
        timestamp = Get-Date -Format 'o'
        level = $Level
        source = 'PKI-Consolidation'
        host = $env:COMPUTERNAME
        message = $Message
    } | ConvertTo-Json
    
    try {
        Invoke-RestMethod -Uri $SIEMEndpoint -Method Post -Body $payload -ContentType 'application/json' -TimeoutSec 5
    } catch {
        # Silent fail - don't block script execution if SIEM unavailable
        Write-Debug "SIEM forwarding failed: $($_.Exception.Message)"
    }
}

# Add to Write-Log function
if ($Global:SIEMEnabled -and $Level -in @('WARN','ERROR')) {
    Send-ToSIEM -Message $Msg -Level $Level
}
```

---

## 5. Network Security

### 5.1 TLS/SSL Configuration

**Enforce TLS 1.2+ for all HTTPS connections**:

```powershell
# Add to Bootstrap section
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Write-Log "Enforced TLS 1.2+ for network connections"
```

### 5.2 Certificate Pinning (Keyfactor API)

```powershell
function Invoke-RestMethodSecure {
    param(
        [string]$Uri,
        [string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [string]$Body,
        [string]$PinnedThumbprint
    )
    
    $callback = {
        param($sender, $cert, $chain, $errors)
        
        # Check certificate thumbprint
        if ($PinnedThumbprint) {
            $actualThumbprint = $cert.Thumbprint
            if ($actualThumbprint -ne $PinnedThumbprint) {
                Write-Log "Certificate pinning failed. Expected: $PinnedThumbprint, Got: $actualThumbprint" 'ERROR'
                return $false
            }
        }
        
        # Standard validation
        return $errors -eq [System.Net.Security.SslPolicyErrors]::None
    }
    
    # Temporarily set validation callback
    $prevCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $callback
    
    try {
        $params = @{
            Uri = $Uri
            Method = $Method
            Headers = $Headers
        }
        if ($Body) { $params.Body = $Body }
        
        return Invoke-RestMethod @params
    } finally {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $prevCallback
    }
}

# Usage
$pinnedThumbprint = 'ABCDEF1234567890...'  # Store securely
Invoke-RestMethodSecure -Uri $KeyfactorUrl -Method POST -Body $payload -PinnedThumbprint $pinnedThumbprint
```

### 5.3 Network Segmentation Validation

```powershell
function Test-NetworkSegmentation {
    # Verify script is running in management VLAN
    $managementSubnets = @('10.10.10.0/24', '192.168.100.0/24')
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } | Select-Object -First 1).IPAddress
    
    $inManagementVLAN = $false
    foreach ($subnet in $managementSubnets) {
        if (Test-IPInSubnet -IPAddress $localIP -Subnet $subnet) {
            $inManagementVLAN = $true
            break
        }
    }
    
    if (-not $inManagementVLAN) {
        Write-Log "WARNING: Script not running from management VLAN. Current IP: $localIP" 'WARN'
    } else {
        Write-Log "Network segmentation verified: Running from management VLAN ($localIP)"
    }
}

function Test-IPInSubnet {
    param([string]$IPAddress, [string]$Subnet)
    
    $ip = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    $subnetParts = $Subnet.Split('/')
    $subnetIP = [System.Net.IPAddress]::Parse($subnetParts[0]).GetAddressBytes()
    $maskBits = [int]$subnetParts[1]
    
    $mask = [byte[]]::new(4)
    for ($i = 0; $i < 4; $i++) {
        $mask[$i] = [byte](([Math]::Pow(2, [Math]::Min(8, $maskBits)) - 1) -shl (8 - [Math]::Min(8, $maskBits)))
        $maskBits -= 8
    }
    
    for ($i = 0; $i < 4; $i++) {
        if (($ip[$i] -band $mask[$i]) -ne ($subnetIP[$i] -band $mask[$i])) {
            return $false
        }
    }
    return $true
}
```

---

## 6. Code Security

### 6.1 Input Validation

**Add validation functions**:

```powershell
function Test-SafePath {
    param([string]$Path)
    
    # Block path traversal
    if ($Path -match '\.\.' -or $Path -match '\\\\') {
        throw "Invalid path detected (path traversal attempt): $Path"
    }
    
    # Block UNC paths (if not expected)
    if ($Path -match '^\\\\')-and -not $Global:AllowUNCPaths) {
        throw "UNC paths not allowed: $Path"
    }
    
    # Normalize path
    try {
        $normalized = [System.IO.Path]::GetFullPath($Path)
        return $normalized
    } catch {
        throw "Invalid path format: $Path"
    }
}

function Test-SafeFileName {
    param([string]$FileName)
    
    # Block invalid characters
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        if ($FileName.Contains($char)) {
            throw "Invalid file name character detected: $char in $FileName"
        }
    }
    
    # Block reserved names
    $reservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'LPT1')
    if ($FileName.ToUpper() -in $reservedNames) {
        throw "Reserved file name not allowed: $FileName"
    }
    
    return $FileName
}

function Test-SafeCAName {
    param([string]$CAName)
    
    # Only allow alphanumeric, dash, underscore
    if ($CAName -notmatch '^[a-zA-Z0-9\-_]+$') {
        throw "Invalid CA name format: $CAName (only alphanumeric, dash, underscore allowed)"
    }
    
    return $CAName
}
```

**Apply validation in phases**:

```powershell
# Example: Phase 3 CSR generation (line 270)
$base = ($s.CA_CN -replace '[^\w\-]','_')
$base = Test-SafeFileName -FileName $base  # <-- Add validation

$infPath = Test-SafePath -Path (Join-Path "$OutDir\work" "$base.subca.inf")
$reqPath = Test-SafePath -Path (Join-Path "$OutDir\work" "$base.subca.req")
```

### 6.2 Code Signing

**Sign the script**:

```powershell
# 1. Obtain code-signing certificate
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1

# 2. Sign script
Set-AuthenticodeSignature -FilePath .\PKI-Consolidation.ps1 -Certificate $cert -TimestampServer 'http://timestamp.digicert.com'

# 3. Verify signature
$sig = Get-AuthenticodeSignature -FilePath .\PKI-Consolidation.ps1
if ($sig.Status -eq 'Valid') {
    Write-Host "[OK] Script signature valid" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Script signature invalid: $($sig.Status)" -ForegroundColor Red
}
```

**Enforce signature validation**:

```powershell
# Add to Bootstrap section
$scriptPath = $PSCommandPath
$signature = Get-AuthenticodeSignature -FilePath $scriptPath

if ($signature.Status -ne 'Valid') {
    throw "Script signature validation failed: $($signature.Status). Script may have been tampered with."
}

$trustedPublishers = @('CN=Contoso Code Signing, O=Contoso, C=US')
if ($signature.SignerCertificate.Subject -notin $trustedPublishers) {
    throw "Script not signed by trusted publisher. Signer: $($signature.SignerCertificate.Subject)"
}

Write-Log "Script signature validated: $($signature.SignerCertificate.Subject)"
```

### 6.3 Dependency Verification

**Verify module integrity**:

```powershell
function Test-ModuleIntegrity {
    param([string]$ModuleName, [string]$ExpectedPublisher = 'CN=Microsoft Corporation')
    
    $module = Get-Module -ListAvailable -Name $ModuleName | Select-Object -First 1
    if (-not $module) {
        throw "Required module not installed: $ModuleName"
    }
    
    # Check module signature (if .ps1 files are signed)
    $moduleFiles = Get-ChildItem -Path $module.ModuleBase -Filter *.ps1 -Recurse
    foreach ($file in $moduleFiles) {
        $sig = Get-AuthenticodeSignature -FilePath $file.FullName
        if ($sig.Status -ne 'Valid' -and $sig.Status -ne 'NotSigned') {
            Write-Log "Module file signature invalid: $($file.FullName)" 'WARN'
        }
    }
    
    Write-Log "Module integrity verified: $ModuleName"
}

# Verify critical modules
Test-ModuleIntegrity -ModuleName 'ActiveDirectory'
Test-ModuleIntegrity -ModuleName 'PSPKI'
```

---

## 7. Operational Security

### 7.1 Least Privilege Execution

**Service Account Creation**:

```powershell
# Create dedicated service account (run once)
$svcAccount = 'PKI-ToolSvc'
$svcPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
$securePassword = ConvertTo-SecureString $svcPassword -AsPlainText -Force

New-ADUser -Name $svcAccount `
    -AccountPassword $securePassword `
    -Enabled $true `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Description "PKI Consolidation Tool Service Account"

# Grant minimum required permissions
Add-ADGroupMember -Identity "Enterprise Admins" -Members $svcAccount

# Schedule script execution
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-File C:\PKI\Consolidation\PKI-Consolidation.ps1 -Phase Audit'
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
$principal = New-ScheduledTaskPrincipal -UserId "DOMAIN\$svcAccount" -LogonType Password
Register-ScheduledTask -TaskName 'PKI-Daily-Audit' -Action $action -Trigger $trigger -Principal $principal
```

### 7.2 Change Control Integration

**Git Integration for Guarded Mode**:

```powershell
function Submit-ChangeForReview {
    param(
        [string]$PatchFilePath,
        [string]$GitRepoPath = 'C:\Git\PKI-Changes'
    )
    
    if (-not (Test-Path $GitRepoPath)) {
        git clone https://git.contoso.com/pki/changes.git $GitRepoPath
    }
    
    # Copy patch to git repo
    $fileName = Split-Path $PatchFilePath -Leaf
    Copy-Item $PatchFilePath -Destination "$GitRepoPath\patches\$fileName"
    
    # Commit and push for review
    Push-Location $GitRepoPath
    try {
        git add "patches\$fileName"
        git commit -m "PKI Registry Change: $fileName - Generated by $env:USERNAME on $(Get-Date -Format 'yyyy-MM-dd')"
        git push origin main
        
        Write-Log "Change submitted for review: $fileName"
        Write-Host "[OK] Change submitted to Git. Create PR for approval." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# Integrate into Phase 4B (after line 500)
if ($patchPath) {
    Submit-ChangeForReview -PatchFilePath $patchPath
    Write-Log "Review patch in Git before applying. Toggle ApplyGuardedChanges when approved."
}
```

### 7.3 Backup Before Modifications

**Enhanced backup with versioning**:

```powershell
function Backup-CAConfiguration {
    param([string]$CAName)
    
    $backupDir = Join-Path $OutDir "backups\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    
    # Backup registry
    $regKey = "HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$CAName"
    $regBackup = Join-Path $backupDir "$CAName-registry.reg"
    & reg export "$regKey" "$regBackup" /y | Out-Null
    
    # Backup CA database
    $dbBackup = Join-Path $backupDir "$CAName-database.bak"
    & certutil -backup "$dbBackup" | Out-Null
    
    # Backup CA certificate
    $caCert = Get-ChildItem Cert:\LocalMachine\CA | Where-Object { $_.Subject -match $CAName } | Select-Object -First 1
    if ($caCert) {
        $certBackup = Join-Path $backupDir "$CAName-certificate.pfx"
        $pfxPassword = ConvertTo-SecureString -String (New-Guid).ToString() -Force -AsPlainText
        Export-PfxCertificate -Cert $caCert -FilePath $certBackup -Password $pfxPassword | Out-Null
        
        # Store password securely
        $pfxPassword | ConvertFrom-SecureString | Out-File "$certBackup.password"
    }
    
    # Create backup manifest
    $manifest = @{
        BackupDate = Get-Date -Format 'o'
        CAName = $CAName
        User = $env:USERNAME
        Computer = $env:COMPUTERNAME
        Files = @(Get-ChildItem $backupDir).Name
    } | ConvertTo-Json
    
    $manifest | Out-File (Join-Path $backupDir 'manifest.json')
    
    Write-Log "Comprehensive backup created: $backupDir"
    return $backupDir
}
```

---

## 8. Compliance Checklist

### 8.1 Pre-Production Security Audit

- [ ] **Credentials**: API keys stored in secure credential manager (not plaintext)
- [ ] **Permissions**: Script validates admin/EA privileges before execution
- [ ] **File ACLs**: Sensitive directories restricted to SYSTEM + Administrators
- [ ] **Logging**: HMAC integrity protection enabled for audit logs
- [ ] **Logging**: Logs forwarded to SIEM for centralized monitoring
- [ ] **Network**: TLS 1.2+ enforced for all HTTPS connections
- [ ] **Network**: Certificate pinning implemented for external APIs
- [ ] **Code**: Script digitally signed with trusted code-signing certificate
- [ ] **Code**: Input validation applied to all user-controlled data
- [ ] **Operational**: Backups created before all destructive operations
- [ ] **Operational**: Change management integration (Git/ServiceNow)
- [ ] **Operational**: PowerShell transcription enabled for session recording
- [ ] **Documentation**: Runbooks updated with security procedures
- [ ] **Testing**: Penetration testing completed and vulnerabilities remediated

### 8.2 Ongoing Security Monitoring

**Monthly Tasks**:
- [ ] Review audit logs for anomalous activity
- [ ] Rotate API keys and service account passwords
- [ ] Verify log integrity with HMAC validation
- [ ] Review file system permissions on sensitive directories
- [ ] Scan for outdated PowerShell modules (security updates)

**Quarterly Tasks**:
- [ ] Conduct security code review of any script modifications
- [ ] Test disaster recovery procedures
- [ ] Review and update threat model
- [ ] Penetration test (if significant changes made)

**Annual Tasks**:
- [ ] Full security audit by external party
- [ ] Compliance assessment (SOC 2, ISO 27001, etc.)
- [ ] Update security documentation

### 8.3 Incident Response

**Security Incident Playbook**:

1. **Detection**:
   - Alert: Tampered log entries detected
   - Alert: Unauthorized script execution
   - Alert: Unexpected registry modifications

2. **Containment**:
   ```powershell
   # Immediately disable script execution
   Set-ExecutionPolicy Restricted -Scope LocalMachine -Force
   
   # Revoke service account permissions
   Remove-ADGroupMember -Identity "Enterprise Admins" -Members "PKI-ToolSvc" -Confirm:$false
   
   # Rotate all credentials
   Update-PKICredential -Target "KeyfactorAPIKey" -NewPassword (Read-Host -AsSecureString)
   ```

3. **Investigation**:
   - Review PowerShell transcripts in `$OutDir\transcripts\`
   - Analyze audit logs for timeline of events
   - Check registry backups for unauthorized changes
   - Review SIEM for correlated events

4. **Recovery**:
   - Restore from last known good backup
   - Re-validate all certificates and chains
   - Reissue certificates if private keys compromised

5. **Lessons Learned**:
   - Document incident in change management system
   - Update threat model and security controls
   - Brief stakeholders on findings

---

## Appendix A: Security Configuration Quick Reference

```powershell
# Complete security hardening script
function Enable-PKISecurity {
    # 1. Privilege validation
    Test-RequiredPrivileges
    
    # 2. Secure credential storage
    Set-PKICredential -Target "KeyfactorAPIKey" -Password (Read-Host -AsSecureString)
    Set-PKICredential -Target "LogHMACKey" -Password (ConvertTo-SecureString (New-Guid) -AsPlainText -Force)
    
    # 3. File permissions
    Set-SecureDirectoryPermissions -Path "C:\PKI\Consolidation\config"
    Set-SecureDirectoryPermissions -Path "C:\PKI\Consolidation\work"
    
    # 4. Enable PowerShell transcription
    $transcriptDir = "C:\PKI\Consolidation\transcripts"
    New-Item -Path $transcriptDir -ItemType Directory -Force
    Start-Transcript -Path "$transcriptDir\setup-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    
    # 5. Code signing
    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
    Set-AuthenticodeSignature -FilePath .\PKI-Consolidation.ps1 -Certificate $cert
    
    # 6. Network security
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    Write-Host "[OK] PKI Security hardening complete" -ForegroundColor Green
}

# Execute
Enable-PKISecurity
```

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-18  
**Next Review**: 2026-01-18  
**Author**: Adrian Johnson <adrian207@gmail.com>

---

For security questions or concerns, please contact: **adrian207@gmail.com**


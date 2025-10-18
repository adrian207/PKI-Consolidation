# PKI-Consolidation Tool - Deployment Guide

**Version:** 1.0  
**Date:** October 18, 2025

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Installation](#2-installation)
3. [Configuration](#3-configuration)
4. [Deployment Procedures](#4-deployment-procedures)
5. [Validation](#5-validation)
6. [Troubleshooting](#6-troubleshooting)

---

## 1. Prerequisites

### 1.1 System Requirements

#### Minimum Requirements
- **Operating System**: Windows Server 2016 or later / Windows 10 Enterprise
- **PowerShell**: Version 5.1 or later
- **Memory**: 4 GB RAM
- **Disk Space**: 10 GB free space
- **.NET Framework**: 4.7.2 or later

#### Recommended Requirements
- **Operating System**: Windows Server 2022
- **PowerShell**: Version 7.4 or later
- **Memory**: 8 GB RAM
- **Disk Space**: 50 GB free space (for large PKI environments)
- **Network**: 1 Gbps connection to domain controllers

### 1.2 Software Dependencies

| Component | Required | Purpose | Installation |
|-----------|----------|---------|--------------|
| **RSAT: Active Directory** | Yes | AD object queries | `Install-WindowsFeature RSAT-AD-PowerShell` |
| **AD CS Admin Tools** | Yes (if managing CAs) | Certificate operations | `Install-WindowsFeature RSAT-ADCS-Mgmt` |
| **PSPKI Module** | Recommended | Enhanced PKI operations | `Install-Module -Name PSPKI` |
| **Azure CLI** | Optional | AKV integration | https://aka.ms/installazurecliwindows |

#### Installation Commands

**PowerShell (Run as Administrator)**:
```powershell
# Install RSAT tools
Install-WindowsFeature RSAT-AD-PowerShell, RSAT-ADCS-Mgmt -IncludeAllSubFeature

# Install PSPKI module
Install-Module -Name PSPKI -Force -AllowClobber

# Verify installations
Get-Module -ListAvailable ActiveDirectory, PSPKI
```

**Azure CLI** (if using Azure Key Vault):
```powershell
# Download and install
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
Start-Process msiexec.exe -ArgumentList '/i', 'AzureCLI.msi', '/quiet' -Wait

# Verify
az --version
```

### 1.3 Permissions Requirements

#### Required Permissions

| Operation | Permission Level | Group Membership |
|-----------|-----------------|------------------|
| **Phase 1 (Audit)** | Domain User + Enterprise Admin | Enterprise Admins |
| **Phase 2-3 (CSR Gen)** | Local Administrator | Administrators |
| **Phase 4 (Publish to AD)** | Enterprise Admin | Enterprise Admins |
| **Phase 4A-4B (Registry)** | Local Administrator + CA Admin | Administrators, CA Admins |
| **Phase 5-7** | Enterprise Admin | Enterprise Admins |
| **Phase 8-9** | Enterprise Admin | Enterprise Admins |

#### Permission Validation Script

```powershell
# Save as Test-PKIPermissions.ps1
function Test-PKIPermissions {
    $results = @()
    
    # Check local administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $results += [PSCustomObject]@{
        Check = 'Local Administrator'
        Status = if ($isAdmin) { 'PASS' } else { 'FAIL' }
        Required = 'Yes'
    }
    
    # Check Enterprise Admin membership
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $configNC = (Get-ADRootDSE).ConfigurationNamingContext
        $domain = $configNC -replace '^.*?DC=','' -replace ',DC=','.'
        $enterpriseAdmins = Get-ADGroup "Enterprise Admins" -Server $domain
        $isMember = (Get-ADGroupMember $enterpriseAdmins -Recursive | Where-Object { $_.SID -eq $user.User }) -ne $null
        
        $results += [PSCustomObject]@{
            Check = 'Enterprise Admin'
            Status = if ($isMember) { 'PASS' } else { 'WARN' }
            Required = 'Yes (for AD operations)'
        }
    } catch {
        $results += [PSCustomObject]@{
            Check = 'Enterprise Admin'
            Status = 'ERROR'
            Required = "Could not verify: $($_.Exception.Message)"
        }
    }
    
    # Check CA admin rights (if CertSvc exists)
    $certSvc = Get-Service CertSvc -ErrorAction SilentlyContinue
    if ($certSvc) {
        $caAdmin = $false
        try {
            $test = & certutil -ping 2>&1
            if ($LASTEXITCODE -eq 0) { $caAdmin = $true }
        } catch { }
        
        $results += [PSCustomObject]@{
            Check = 'CA Administrator'
            Status = if ($caAdmin) { 'PASS' } else { 'WARN' }
            Required = 'Yes (for registry changes)'
        }
    }
    
    $results | Format-Table -AutoSize
    
    $failures = $results | Where-Object { $_.Status -eq 'FAIL' }
    if ($failures) {
        Write-Host "`n[ERROR] Missing required permissions. Please run as an Enterprise Admin." -ForegroundColor Red
        return $false
    }
    
    return $true
}

# Execute
Test-PKIPermissions
```

### 1.4 Network Requirements

| Destination | Port | Protocol | Purpose |
|-------------|------|----------|---------|
| Domain Controllers | 389, 636 | LDAP/LDAPS | AD queries |
| Domain Controllers | 88 | Kerberos | Authentication |
| Certificate Authorities | 135 | RPC | Certificate operations |
| OCSP Responders | 80, 443 | HTTP/HTTPS | Revocation checking |
| Azure | 443 | HTTPS | Cloud integration |
| Keyfactor Server | 443 | HTTPS | API calls |

#### Network Validation Script

```powershell
function Test-PKIConnectivity {
    $tests = @()
    
    # Test DC connectivity
    try {
        $dc = (Get-ADDomainController -Discover -ErrorAction Stop).HostName
        $ldap = Test-NetConnection -ComputerName $dc -Port 389 -WarningAction SilentlyContinue
        $tests += [PSCustomObject]@{
            Target = "Domain Controller ($dc)"
            Port = 389
            Status = if ($ldap.TcpTestSucceeded) { 'PASS' } else { 'FAIL' }
        }
    } catch {
        $tests += [PSCustomObject]@{
            Target = 'Domain Controller'
            Port = 389
            Status = "ERROR: $($_.Exception.Message)"
        }
    }
    
    # Test internet connectivity (for Azure)
    $internet = Test-NetConnection -ComputerName login.microsoftonline.com -Port 443 -WarningAction SilentlyContinue
    $tests += [PSCustomObject]@{
        Target = 'Azure (login.microsoftonline.com)'
        Port = 443
        Status = if ($internet.TcpTestSucceeded) { 'PASS' } else { 'WARN (Optional)' }
    }
    
    $tests | Format-Table -AutoSize
}

Test-PKIConnectivity
```

---

## 2. Installation

### 2.1 Download Script

**Option A: Git Clone**
```powershell
# Clone repository
cd C:\
git clone https://github.com/your-org/PKI-Consolidation.git
cd PKI-Consolidation
```

**Option B: Manual Download**
1. Download `PKI-Consolidation.ps1` from your repository/share
2. Place in `C:\PKI\Consolidation\`
3. Unblock file: `Unblock-File -Path C:\PKI\Consolidation\PKI-Consolidation.ps1`

### 2.2 Verify File Integrity

```powershell
# Calculate file hash
$hash = Get-FileHash -Path .\PKI-Consolidation.ps1 -Algorithm SHA256

# Compare against known good hash (obtain from secure channel)
$expectedHash = "YOUR_EXPECTED_HASH_HERE"

if ($hash.Hash -eq $expectedHash) {
    Write-Host "[OK] File integrity verified" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Hash mismatch! File may be corrupted or tampered." -ForegroundColor Red
}
```

### 2.3 Set Execution Policy

```powershell
# Check current policy
Get-ExecutionPolicy

# Set policy (choose appropriate level)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Or sign the script with your code-signing certificate
Set-AuthenticodeSignature -FilePath .\PKI-Consolidation.ps1 -Certificate $cert
```

### 2.4 Create Directory Structure

The script automatically creates required directories on first run:
```
C:\PKI\Consolidation\
├── config\
├── exports\
├── reports\
├── work\
│   └── issued\
└── PKI-Consolidation.log
```

**Manual Creation** (if needed):
```powershell
$baseDir = 'C:\PKI\Consolidation'
'config', 'exports', 'reports', 'work', 'work\issued' | ForEach-Object {
    New-Item -Path "$baseDir\$_" -ItemType Directory -Force
}
```

---

## 3. Configuration

### 3.1 Edit Script Variables

Open `PKI-Consolidation.ps1` and edit lines 58-74:

```powershell
# Output directory
$Global:OutDir = 'C:\PKI\Consolidation'

# Authoritative root (leave $null to auto-detect)
$Global:AuthoritativeRootCN = $null
# Example: 'CN=Contoso Root CA, DC=contoso, DC=com'

# Azure Key Vault (leave blank to skip)
$Global:VaultName = ''  # e.g., 'contoso-pki-vault'

# Keyfactor settings (leave blank to skip)
$Global:KeyfactorBaseUrl = ''  # e.g., 'https://keyfactor.contoso.com'
$Global:KeyfactorApiKey  = ''  # Store securely! See security guide

# Safety toggles
$Global:DoDryRun = $false             # Set $true to preview without executing
$Global:GuardedMode = $true           # Stage registry changes as .reg files
$Global:ApplyGuardedChanges = $false  # Set $true to auto-apply patches
$Global:EnableVerboseLog = $true      # Enable detailed logging
```

### 3.2 Configure CRL/AIA/OCSP Settings

Edit `C:\PKI\Consolidation\config\crl-aia-ocsp.json`:

```json
{
  "CAs": [
    {
      "CAName": "Contoso-RootCA",
      "Additions": {
        "CRLPublicationURLs": [
          "65:file://C:\\PKI\\CRL\\%3%8%9.crl",
          "79:http://pki.contoso.com/crl/%3%8%9.crl",
          "2:ldap:///CN=%7%8,CN=%2,CN=CDP,CN=Public Key Services,CN=Services,%6%10"
        ],
        "CACertPublicationURLs": [
          "1:file://C:\\PKI\\AIA\\%3%4.crt",
          "2:ldap:///CN=%7,CN=AIA,CN=Public Key Services,CN=Services,%6%11",
          "32:http://pki.contoso.com/aia/%3%4.crt"
        ],
        "AuthorityInformationAccess": [
          "1:CERT_OCSP_URL_PROP_ID:http://ocsp.contoso.com/ocsp",
          "2:CERT_AIA_URL_PROP_ID:http://pki.contoso.com/aia/%3%4.crt"
        ]
      }
    },
    {
      "CAName": "Contoso-IssuingCA1",
      "Additions": {
        "CRLPublicationURLs": [
          "65:file://C:\\PKI\\CRL\\%3%8%9.crl",
          "79:http://pki.contoso.com/crl/%3%8%9.crl"
        ],
        "CACertPublicationURLs": [
          "1:file://C:\\PKI\\AIA\\%3%4.crt",
          "32:http://pki.contoso.com/aia/%3%4.crt"
        ],
        "AuthorityInformationAccess": [
          "1:CERT_OCSP_URL_PROP_ID:http://ocsp.contoso.com/ocsp"
        ]
      }
    }
  ]
}
```

**Token Reference**:
- `%1`: Server DNS hostname
- `%2`: CA sanitized name
- `%3`: CA sanitized short name
- `%4`: CA cert suffix (.crt)
- `%8`: CRL name suffix
- `%9`: CRL suffix (.crl)
- `%10`: Delta CRL suffix
- `%11`: Cert suffix (.cer)

### 3.3 Azure Key Vault Setup (Optional)

```powershell
# Login to Azure
az login

# Create resource group
az group create --name rg-pki-prod --location eastus

# Create Key Vault
az keyvault create \
  --name contoso-pki-vault \
  --resource-group rg-pki-prod \
  --location eastus \
  --enable-rbac-authorization false

# Grant current user Certificate Import permission
$upn = (az account show --query user.name -o tsv)
az keyvault set-policy \
  --name contoso-pki-vault \
  --upn $upn \
  --certificate-permissions import get list

# Update script configuration
$Global:VaultName = 'contoso-pki-vault'
```

### 3.4 Keyfactor Setup (Optional)

```powershell
# Obtain API key from Keyfactor portal
# Settings > Security > API Keys > Generate New API Key

# Store securely in Windows Credential Manager
$cred = Get-Credential -UserName 'KeyfactorAPIKey' -Message 'Enter Keyfactor API Key'
$cred.Password | ConvertFrom-SecureString | Out-File .\keyfactor-api-key.txt

# Load in script
$encryptedKey = Get-Content .\keyfactor-api-key.txt | ConvertTo-SecureString
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($encryptedKey)
$Global:KeyfactorApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
$Global:KeyfactorBaseUrl = 'https://keyfactor.contoso.com'
```

---

## 4. Deployment Procedures

### 4.1 Pre-Deployment Checklist

- [ ] **Backups completed**: CA database, registry, private keys
- [ ] **Change control approved**: Ticket # ____________
- [ ] **Maintenance window scheduled**: Date/Time ____________
- [ ] **Permissions validated**: Run `Test-PKIPermissions.ps1`
- [ ] **Network connectivity verified**: Run `Test-PKIConnectivity`
- [ ] **Dependencies installed**: RSAT, PSPKI, Azure CLI (if applicable)
- [ ] **Configuration reviewed**: Script variables and JSON config
- [ ] **Stakeholders notified**: Email sent to affected teams
- [ ] **Rollback plan documented**: See section 4.6

### 4.2 Step-by-Step Deployment

#### Step 1: Initial Audit (Read-Only)

```powershell
# Launch script
cd C:\PKI\Consolidation
.\PKI-Consolidation.ps1

# From menu, select:
# 1) Audit CAs

# Review output
notepad C:\PKI\Consolidation\reports\CA-Inventory.csv
```

**Expected Output**:
- CSV file with all discovered CAs
- Certificate details (Subject, Issuer, Algorithm, Expiration)
- Template assignments

**Validation**:
- Verify all expected CAs are listed
- Check for weak signature algorithms (MD5, SHA-1)
- Identify expired or near-expiring certificates

#### Step 2: Select Authoritative Root

```powershell
# From menu, select:
# 2) Select/Set Authoritative Root

# Review selection
Get-Content C:\PKI\Consolidation\reports\AuthoritativeRoot.txt
```

**Expected Output**:
- Single root CA distinguished name
- Should be SHA-2 signed if available

**Manual Override** (if auto-selection is incorrect):
```powershell
# Edit script line 59:
$Global:AuthoritativeRootCN = 'CN=Contoso Root CA, O=Contoso, C=US'

# Re-run Phase 2
```

#### Step 3: Generate Sub-CA CSRs

```powershell
# From menu, select:
# 3) Generate Sub-CA CSRs

# Review generated requests
Get-ChildItem C:\PKI\Consolidation\work\*.req
Get-Content C:\PKI\Consolidation\work\SubCA1.subca.inf
```

**Expected Output**:
- `.inf` file for each sub-CA
- `.req` file (PKCS#10 request)

**Validation**:
- Verify Subject DN matches existing CA
- Confirm KeyLength = 4096, HashAlgorithm = sha256

#### Step 4: Submit CSRs to Root CA

**Manual Process**:
1. Copy `.req` files to root CA server
2. Open Certification Authority console
3. Right-click CA name → All Tasks → Submit new request
4. Select `.req` file
5. Approve pending request
6. Export issued certificate (Base-64 encoded)
7. Copy `.cer` file to `C:\PKI\Consolidation\work\issued\` on tool server

**Automated Process** (if certutil can reach CA):
```powershell
$rootCA = 'RootCA-Server\Contoso Root CA'

Get-ChildItem C:\PKI\Consolidation\work\*.req | ForEach-Object {
    $reqFile = $_.FullName
    $cerFile = $reqFile -replace '\.req$', '.cer'
    
    # Submit request
    $submit = & certutil -config $rootCA -submit $reqFile $cerFile
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Issued: $($_.Name)" -ForegroundColor Green
        
        # Move to issued folder
        Move-Item $cerFile -Destination C:\PKI\Consolidation\work\issued\
    } else {
        Write-Host "[ERROR] Failed: $($_.Name)" -ForegroundColor Red
    }
}
```

#### Step 5: Accept and Publish Certificates

```powershell
# Verify issued certificates are present
Get-ChildItem C:\PKI\Consolidation\work\issued\*.cer

# From menu, select:
# 4) Accept Issued Sub-CA Certs + Publish to AD

# Monitor log for errors
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log -Tail 20 -Wait
```

**Expected Output**:
- Certificates installed to LocalMachine\CA store
- Root published to AD (CN=Certification Authorities)
- Sub-CAs published to AD (CN=AIA)
- Issuing CAs published to NTAuth

**Validation**:
```powershell
# Verify certificate stores
Get-ChildItem Cert:\LocalMachine\CA

# Verify AD publication
certutil -viewstore "ldap:///CN=Certification Authorities,CN=Public Key Services,CN=Services,CN=Configuration,DC=contoso,DC=com?cACertificate"
```

#### Step 6: Publish CRL/AIA & Check OCSP

```powershell
# From menu, select:
# 4A) Publish CRL/AIA & OCSP health check

# Monitor operations
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log -Tail 50
```

**Expected Output**:
- Fresh CRL generated for each CA
- CRL published to AD
- CRL copied to file system paths
- CA certificates copied to AIA paths
- OCSP endpoints probed (if configured)

**Validation**:
```powershell
# Check CRL freshness
$crlPath = "C:\Windows\System32\CertSrv\CertEnroll\*.crl"
Get-ChildItem $crlPath | Select-Object Name, LastWriteTime

# Verify CRL content
certutil -dump (Get-ChildItem $crlPath | Select-Object -First 1).FullName
```

#### Step 7: Stage and Apply Registry Changes (Guarded Mode)

```powershell
# Enable dry-run first (safety)
# From menu, select:
# D) Toggle Dry-Run (set to $true)

# From menu, select:
# 4B) Stage & (optionally) APPLY Guarded Registry Changes

# Review staged patches
notepad (Get-ChildItem C:\PKI\Consolidation\work\*-patch.reg | Sort LastWriteTime -Desc | Select -First 1).FullName
```

**Review Checklist**:
- [ ] Backup .reg file created with timestamp
- [ ] Patch .reg file contains only expected additions
- [ ] No unexpected deletions or modifications
- [ ] URLs are correct and accessible
- [ ] Flag encodings match requirements

**Apply Changes**:
```powershell
# Disable dry-run
# From menu: D) Toggle Dry-Run (set to $false)

# Enable apply
# From menu: A) Toggle Apply-Guarded-Changes (set to $true)

# Run Phase 4B again
# From menu: 4B) Stage & (optionally) APPLY Guarded Registry Changes

# Verify CA service restarted successfully
Get-Service CertSvc
certutil -ping
```

**Rollback** (if issues occur):
```powershell
Stop-Service CertSvc -Force
$backup = Get-ChildItem C:\PKI\Consolidation\work\*-backup.reg | Sort LastWriteTime -Desc | Select -First 1
reg import $backup.FullName /y
Start-Service CertSvc
certutil -ping
```

#### Step 8: Trust Propagation via GPO

```powershell
# From menu, select:
# 5) Trust Propagation (GPO helper)

# Review generated INF
notepad C:\PKI\Consolidation\work\trustedroots.inf
```

**Deploy via Group Policy**:
1. Open Group Policy Management Console
2. Create new GPO: "PKI - Trusted Root Certificates"
3. Edit GPO → Computer Configuration → Windows Settings → Security Settings → Public Key Policies
4. Right-click "Trusted Root Certification Authorities" → Import
5. Select authoritative root certificate from `exports\` folder
6. Link GPO to appropriate OUs
7. Force update: `gpupdate /force /target:computer`

#### Step 9: Cloud Integration (Optional)

```powershell
# From menu, select:
# 6) Cloud Integrations (AKV / Keyfactor)

# Verify Azure Key Vault import
az keyvault certificate show --vault-name contoso-pki-vault --name EnterpriseRoot

# Verify Keyfactor registration (via portal or API)
$headers = @{
    'x-keyfactor-requested-with' = 'APIClient'
    'Authorization' = "Bearer $Global:KeyfactorApiKey"
}
Invoke-RestMethod -Uri "$($Global:KeyfactorBaseUrl)/KeyfactorAPI/CertificateAuthorities" -Headers $headers
```

#### Step 10: Trigger Leaf Certificate Re-issuance

```powershell
# From menu, select:
# 7) Leaf Re-issuance Triggers

# Verify auto-enrollment triggered
Get-EventLog -LogName Application -Source Microsoft-Windows-CertificateServicesClient-AutoEnrollment -Newest 10
```

**Force Re-enrollment** (if needed):
```powershell
# On client machines
gpupdate /force
certutil -pulse

# Monitor certificate issuance on CA
Get-EventLog -LogName Application -Source CertificationAuthority -Newest 20 | Where-Object {$_.EventID -eq 58}
```

#### Step 11: Verification

```powershell
# From menu, select:
# 8) Verification Report

# Review report
Import-Csv C:\PKI\Consolidation\reports\Leaf-Verification.csv | Format-Table -AutoSize

# Check chain validation
Import-Csv C:\PKI\Consolidation\reports\Leaf-Verification.csv | Where-Object {$_.ChainsToAuthoritativeRoot -eq $false}
```

**Expected**: All certificates chain to authoritative root (may take time for re-issuance)

#### Step 12: Decommission Legacy CAs (After Validation Period)

**WAIT**: Allow sufficient time for all leaf certificates to be re-issued (recommend 30-90 days)

```powershell
# From menu, select:
# 9) Decommission Legacy CAs (unpublish)

# Review unpublished certificates
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log | Select-String 'Unpublished'
```

**⚠️ IMPORTANT**: Keep legacy CRL distribution points online until all certificates issued by legacy CAs expire!

### 4.3 Deployment Timeline

| Phase | Duration | Dependencies | Risk Level |
|-------|----------|--------------|------------|
| Audit (Phase 1) | 10 min | None | Low |
| Root Selection (Phase 2) | 5 min | Phase 1 | Low |
| CSR Generation (Phase 3) | 15 min | Phase 2 | Low |
| **Manual CSR Submission** | 30 min | Phase 3 | Medium |
| Accept & Publish (Phase 4) | 20 min | Issued certs | Medium |
| CRL/AIA Publish (Phase 4A) | 15 min | Phase 4 | Medium |
| Registry Changes (Phase 4B) | 30 min | Phase 4A | **High** |
| Trust Propagation (Phase 5) | 60 min | Phase 4 | Medium |
| Cloud Integration (Phase 6) | 20 min | Phase 4 | Low |
| Leaf Re-issuance (Phase 7) | 5 min | Phase 5 | Low |
| Verification (Phase 8) | 15 min | Phase 7 | Low |
| **Total Active Time** | ~3.5 hours | | |
| **Total Calendar Time** | 1-7 days | Certificate re-issuance | |

### 4.4 Maintenance Window Requirements

**Minimum Window**: 4 hours

**Window Breakdown**:
- Pre-checks: 30 min
- Phases 1-4: 90 min
- Phases 4A-4B: 60 min (including review)
- Testing & validation: 45 min
- Buffer for issues: 45 min

**Service Impact**:
- **CA Service Restart**: 2-5 minutes (Phase 4B)
- **Certificate Issuance**: Unavailable during restart
- **Certificate Validation**: No impact (existing CRLs remain valid)

### 4.5 Rollback Procedures

#### Scenario 1: Registry Changes Failed

```powershell
# Stop CA service
Stop-Service CertSvc -Force

# Find latest backup
$backup = Get-ChildItem C:\PKI\Consolidation\work\*-backup.reg | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

# Import backup
reg import $backup.FullName /y

# Start CA service
Start-Service CertSvc

# Verify health
certutil -ping
certutil -verify (Get-ChildItem Cert:\LocalMachine\My | Select-Object -First 1).PSPath
```

#### Scenario 2: Certificate Chain Broken

```powershell
# Re-publish root to AD
$rootCer = Get-ChildItem C:\PKI\Consolidation\exports\*RootCA*.cer | Select-Object -First 1
certutil -dspublish -f $rootCer.FullName RootCA

# Re-publish intermediates
Get-ChildItem C:\PKI\Consolidation\work\issued\*.cer | ForEach-Object {
    certutil -dspublish -f $_.FullName SubCA
}

# Force AD replication
repadmin /syncall /AdeP
```

#### Scenario 3: Complete Rollback to Previous State

1. Restore CA database from backup (before consolidation)
2. Import registry backup (created in Phase 4B)
3. Remove new certificates from AD:
   ```powershell
   # CAUTION: This removes objects from AD
   $configNC = (Get-ADRootDSE).ConfigurationNamingContext
   $pkiDN = "CN=Public Key Services,CN=Services,$configNC"
   
   # Remove published certificates (use with extreme caution)
   # Get-ADObject -SearchBase "CN=Certification Authorities,$pkiDN" -Filter * | Remove-ADObject -Confirm:$true
   ```
4. Notify users to revert GPO changes
5. Document rollback in change control system

### 4.6 Post-Deployment Validation

```powershell
# Comprehensive validation script
function Test-PKIDeployment {
    $results = @()
    
    # Test 1: CA service health
    $svc = Get-Service CertSvc -ErrorAction SilentlyContinue
    $results += [PSCustomObject]@{
        Test = 'CA Service Running'
        Result = if ($svc -and $svc.Status -eq 'Running') { 'PASS' } else { 'FAIL' }
    }
    
    # Test 2: CA responsiveness
    $ping = & certutil -ping 2>&1
    $results += [PSCustomObject]@{
        Test = 'CA Responding'
        Result = if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }
    }
    
    # Test 3: CRL freshness
    $crl = Get-ChildItem "C:\Windows\System32\CertSrv\CertEnroll\*.crl" -ErrorAction SilentlyContinue | 
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $crlFresh = if ($crl) { ((Get-Date) - $crl.LastWriteTime).TotalHours -lt 24 } else { $false }
    $results += [PSCustomObject]@{
        Test = 'CRL Fresh (<24h)'
        Result = if ($crlFresh) { 'PASS' } else { 'WARN' }
    }
    
    # Test 4: Certificate store populated
    $caStore = Get-ChildItem Cert:\LocalMachine\CA -ErrorAction SilentlyContinue
    $results += [PSCustomObject]@{
        Test = 'CA Store Populated'
        Result = if ($caStore.Count -gt 0) { 'PASS' } else { 'FAIL' }
    }
    
    # Test 5: Test certificate issuance
    $testCert = $null
    try {
        $testReq = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=PKI-Test-$(Get-Date -Format 'yyyyMMddHHmmss')"
KeyLength = 2048
Exportable = TRUE
MachineKeySet = FALSE
RequestType = Cert

[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.2
"@
        $testReq | Out-File "$env:TEMP\pki-test.inf" -Encoding ASCII
        $result = & certreq -new -q "$env:TEMP\pki-test.inf" "$env:TEMP\pki-test.cer" 2>&1
        $testCert = $LASTEXITCODE -eq 0
    } catch {
        $testCert = $false
    }
    $results += [PSCustomObject]@{
        Test = 'Test Certificate Issuance'
        Result = if ($testCert) { 'PASS' } else { 'FAIL' }
    }
    
    # Test 6: Chain validation
    if ($testCert) {
        $verify = & certutil -verify "$env:TEMP\pki-test.cer" 2>&1
        $chainValid = $verify -match 'Verified'
        $results += [PSCustomObject]@{
            Test = 'Certificate Chain Valid'
            Result = if ($chainValid) { 'PASS' } else { 'FAIL' }
        }
    }
    
    # Display results
    $results | Format-Table -AutoSize
    
    # Summary
    $failed = ($results | Where-Object { $_.Result -eq 'FAIL' }).Count
    $warned = ($results | Where-Object { $_.Result -eq 'WARN' }).Count
    
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Passed: $($results.Count - $failed - $warned)" -ForegroundColor Green
    Write-Host "  Warned: $warned" -ForegroundColor Yellow
    Write-Host "  Failed: $failed" -ForegroundColor Red
    
    if ($failed -eq 0) {
        Write-Host "`n[SUCCESS] PKI deployment validation passed!" -ForegroundColor Green
    } else {
        Write-Host "`n[FAILURE] PKI deployment validation failed. Review errors above." -ForegroundColor Red
    }
}

# Execute validation
Test-PKIDeployment
```

---

## 5. Validation

### 5.1 Functional Testing

| Test Case | Procedure | Expected Result |
|-----------|-----------|-----------------|
| **TC-01: Certificate Issuance** | Request user certificate via MMC | Certificate issued with correct chain |
| **TC-02: Chain Validation** | `certutil -verify <cert.cer>` | Chain builds to authoritative root |
| **TC-03: CRL Access** | `certutil -verify -urlfetch <cert>` | CRL retrieved successfully |
| **TC-04: OCSP Response** | `certutil -verify -urlfetch <cert>` | OCSP response good |
| **TC-05: Smart Card Logon** | Test smart card logon | Authentication successful |
| **TC-06: Auto-Enrollment** | `gpupdate /force; certutil -pulse` | Certificates auto-enrolled |

### 5.2 Security Validation

```powershell
# Check for weak algorithms
Get-ChildItem Cert:\LocalMachine\CA | Where-Object { 
    $_.SignatureAlgorithm.FriendlyName -match 'md5|sha1' 
} | Select Subject, SignatureAlgorithm

# Verify registry permissions
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
Get-Acl $regPath | Format-List

# Check log file permissions
Get-Acl C:\PKI\Consolidation\PKI-Consolidation.log | Format-List
```

### 5.3 Performance Validation

```powershell
# Measure certificate issuance time
Measure-Command {
    certutil -pulse
}

# Check CA queue depth
certutil -view -restrict "Disposition=9" -out "RequestID" | Measure-Object

# Monitor service resource usage
Get-Process -Name CertSvc | Select CPU, WorkingSet, VirtualMemorySize
```

---

## 6. Troubleshooting

### 6.1 Common Issues

#### Issue: "Access Denied" during Phase 1

**Symptoms**: Error when querying AD for PKI objects

**Cause**: Insufficient permissions

**Resolution**:
```powershell
# Verify group membership
whoami /groups | Select-String "Enterprise Admins"

# Add current user to Enterprise Admins (requires Domain Admin)
Add-ADGroupMember -Identity "Enterprise Admins" -Members $env:USERNAME

# Log off and log back in
```

#### Issue: Certificate acceptance fails (Phase 4)

**Symptoms**: `certreq -accept` returns error

**Cause**: Private key not found or certificate/key mismatch

**Resolution**:
```powershell
# Check for pending requests
certutil -store REQUEST

# Verify private key exists
certutil -store MY -v | Select-String "Private Key"

# Delete orphaned request and regenerate CSR
certutil -delstore REQUEST <RequestID>
# Re-run Phase 3
```

#### Issue: CA service won't start after registry change

**Symptoms**: CertSvc service fails to start

**Cause**: Malformed registry value

**Resolution**:
1. Review Application event log: `Get-EventLog -LogName Application -Source CertificationAuthority -Newest 10`
2. Restore registry backup (see Section 4.5.1)
3. Manually edit registry if specific value is identified as problematic

#### Issue: CRL not accessible via HTTP

**Symptoms**: `certutil -verify -urlfetch` shows CRL retrieval failure

**Cause**: IIS not configured, firewall blocking, or file not published

**Resolution**:
```powershell
# Check IIS status
Get-Service W3SVC

# Verify file exists
Test-Path C:\inetpub\wwwroot\pki\crl\*.crl

# Test HTTP access
Invoke-WebRequest -Uri http://pki.contoso.com/crl/ContosoRootCA.crl -UseBasicParsing

# Check firewall
Test-NetConnection -ComputerName pki.contoso.com -Port 80
```

#### Issue: Certificates not auto-enrolling

**Symptoms**: Clients not receiving updated certificates after `certutil -pulse`

**Cause**: GPO not applied, template not published, or permissions incorrect

**Resolution**:
```powershell
# Force GPO update
gpupdate /force /target:computer

# Check template permissions
certutil -template | Select-String -Context 0,20 "Template:"

# Verify CA templates are published
Get-CATemplate -CA "CA-Server\CA-Name"

# Check auto-enrollment event log
Get-WinEvent -LogName Microsoft-Windows-CertificateServicesClient-Lifecycle-System
```

### 6.2 Diagnostic Commands

```powershell
# Comprehensive CA diagnostic
certutil -dump

# View CA configuration
certutil -getreg CA\

# Check certificate chains
certutil -viewstore CA

# Test CRL/OCSP endpoints
certutil -verify -urlfetch C:\path\to\cert.cer

# View pending requests
certutil -view -restrict "Disposition=9"

# Dump certificate details
certutil -dump C:\path\to\cert.cer

# Check AD PKI containers
certutil -viewstore "ldap:///CN=Certification Authorities,CN=Public Key Services,CN=Services,CN=Configuration,DC=contoso,DC=com?cACertificate"
```

### 6.3 Log Analysis

```powershell
# Filter for errors
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log | Select-String "\[ERROR\]"

# Extract Phase 4B operations
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log | Select-String "Phase 4B|Registry|patch"

# View recent activity
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log -Tail 100

# Export filtered log
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log | 
    Where-Object { $_ -match "WARN|ERROR" } | 
    Out-File C:\PKI\Consolidation\reports\Errors-$(Get-Date -Format 'yyyyMMdd').log
```

### 6.4 Support Contacts

| Issue Type | Contact | SLA |
|------------|---------|-----|
| **Script Errors** | PKI Team: pki-team@contoso.com | 4 hours |
| **CA Service Issues** | Infrastructure Team: infra@contoso.com | 1 hour |
| **AD Replication** | Directory Services: ad-team@contoso.com | 2 hours |
| **Network/Firewall** | Network Operations: netops@contoso.com | 2 hours |
| **Security Review** | Security Team: security@contoso.com | 24 hours |

---

## Appendix A: Quick Reference Card

### Essential Commands

```powershell
# Start script
.\PKI-Consolidation.ps1

# Enable dry-run
$Global:DoDryRun = $true

# View logs
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log -Tail 50 -Wait

# Rollback registry
Stop-Service CertSvc -Force
reg import C:\PKI\Consolidation\work\CA-backup.reg /y
Start-Service CertSvc

# Verify CA health
certutil -ping

# Test certificate chain
certutil -verify C:\path\to\cert.cer

# Force client cert renewal
gpupdate /force
certutil -pulse
```

### Phase Execution Order

1. Audit CAs
2. Select Root
3. Gen CSRs → **MANUAL SUBMIT** → Place issued certs in `work/issued/`
4. Accept & Publish
5. Publish CRL/AIA
6. Guarded Registry (Review patch, then apply)
7. Trust Propagation
8. Cloud Integration (if configured)
9. Leaf Re-issuance
10. Verification
11. Decommission (after validation period)

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-18  
**Next Review**: 2026-01-18


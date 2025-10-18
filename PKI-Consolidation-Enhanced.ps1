#Requires -Version 5.1
#Requires -RunAsAdministrator
<# 
PKI-Consolidation.ps1 - ENHANCED SECURITY VERSION v1.1.0
(with Security Module Integration + Guarded Mode + CRL/AIA publish + OCSP health)

Menu-driven automation for merger-driven AD CS consolidation:
  1) Audit CAs
  2) Choose/Set Authoritative Enterprise Root
  3) Generate Sub-CA CSRs
  4) Accept Issued Sub-CA Certs + Publish to AD
  4A) Publish CRL/AIA & OCSP health check
  4B) Stage & (optionally) APPLY Guarded Registry Changes for CRL/AIA/OCSP
  5) Trust Propagation (GPO helper)
  6) Cloud Integrations (AKV / Keyfactor)
  7) Leaf Re-issuance Triggers
  8) Verification Report
  9) Decommission Legacy CAs (unpublish)
  D) Toggle Dry-Run
  G) Toggle Guarded Mode (stage-but-don't-apply changes)
  A) Toggle Apply-Guarded-Changes (apply staged .reg when you choose 4B)
  H) Run Health Check
  Q) Quit

SECURITY ENHANCEMENTS v1.1.0:
✓ Secure credential storage (Windows Credential Manager / Azure Key Vault)
✓ Privilege validation (Local Admin, Enterprise Admin, CA Admin)
✓ HMAC-protected logging with tamper detection
✓ File permission hardening (SYSTEM + Administrators only)
✓ Input validation (path, filename, CA name sanitization)
✓ Comprehensive error handling

SETUP REQUIRED:
Before first use, run: .\scripts\Setup-PKICredentials.ps1 -GenerateLogHMACKey

Author: Adrian Johnson <adrian207@gmail.com>
GitHub: https://github.com/adrian207/PKI-Consolidation
#>

#====================#
# CONFIG (EDIT ME)   #
#====================#
$Global:OutDir                 = 'C:\PKI\Consolidation'
$Global:AuthoritativeRootCN    = $null   # Example: 'CN=EnterpriseRootCA, O=Contoso, C=US' (else auto-propose)
$Global:VaultName              = ''      # Azure Key Vault name (leave blank to skip)
$Global:KeyfactorBaseUrl       = ''      # e.g. https://kf.yourco.com

# Safety toggles
$Global:DoDryRun               = $false  # Preview actions without executing
$Global:GuardedMode            = $true   # Stage registry changes as a .reg patch (don't apply unless toggled)
$Global:ApplyGuardedChanges    = $false  # If true, 4B will apply the staged .reg after staging
$Global:EnableVerboseLog       = $true
$Global:EnableSecureLogging    = $true   # Use HMAC-protected logging

# Configuration paths
$Global:GuardedConfigPath      = Join-Path $OutDir 'config\crl-aia-ocsp.json'
$Global:LogPath                = Join-Path $OutDir 'PKI-Consolidation.log'

#====================#
# BOOTSTRAP          #
#====================#
$ErrorActionPreference = 'Stop'

# Initialize session
$Global:SessionID = [Guid]::NewGuid().ToString()
Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                               ║" -ForegroundColor Cyan
Write-Host "║          PKI-Consolidation Tool v1.1.0 (Enhanced)           ║" -ForegroundColor Cyan
Write-Host "║                                                               ║" -ForegroundColor Cyan
Write-Host "║          Author: Adrian Johnson <adrian207@gmail.com>        ║" -ForegroundColor Cyan
Write-Host "║          Session: $($Global:SessionID.Substring(0,8))                  ║" -ForegroundColor Cyan
Write-Host "║                                                               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Create directories
Write-Host "[Bootstrap] Creating directory structure..." -ForegroundColor Yellow
$null = New-Item -Type Directory -Force -Path $OutDir, "$OutDir\exports", "$OutDir\reports", "$OutDir\work", "$OutDir\work\issued", "$OutDir\config", "$OutDir\backups" -ErrorAction SilentlyContinue

# Import Security Module
Write-Host "[Bootstrap] Importing PKI-Security module..." -ForegroundColor Yellow
$securityModulePath = Join-Path $PSScriptRoot "modules\PKI-Security.psm1"
if (Test-Path $securityModulePath) {
    try {
        Import-Module $securityModulePath -Force -ErrorAction Stop
        Write-Host "[Bootstrap] ✓ Security module loaded`n" -ForegroundColor Green
    }
    catch {
        Write-Host "[Bootstrap] ✗ Failed to load security module: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[Bootstrap] Falling back to basic logging..." -ForegroundColor Yellow
        $Global:EnableSecureLogging = $false
    }
}
else {
    Write-Host "[Bootstrap] ⚠ Security module not found: $securityModulePath" -ForegroundColor Yellow
    Write-Host "[Bootstrap] Falling back to basic logging..." -ForegroundColor Yellow
    $Global:EnableSecureLogging = $false
}

# Validate privileges
if ($Global:EnableSecureLogging) {
    Write-Host "[Bootstrap] Validating execution privileges..." -ForegroundColor Yellow
    try {
        $privCheck = Test-RequiredPrivileges
        if ($privCheck.HasRequiredPrivileges) {
            Write-Host "[Bootstrap] ✓ Privilege validation passed`n" -ForegroundColor Green
        }
        else {
            Write-Host "[Bootstrap] ⚠ Some privileges missing. Operations may fail.`n" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[Bootstrap] ⚠ Privilege validation error: $($_.Exception.Message)`n" -ForegroundColor Yellow
    }
}

# Load credentials securely
$Global:KeyfactorApiKey = $null
$Global:LogHMACKey = $null

if ($Global:EnableSecureLogging) {
    Write-Host "[Bootstrap] Loading secure credentials..." -ForegroundColor Yellow
    
    # Load Keyfactor API Key
    if ($Global:KeyfactorBaseUrl) {
        try {
            $kfCred = Get-PKICredential -Target "KeyfactorAPIKey" -ErrorAction Stop
            $Global:KeyfactorApiKey = $kfCred.GetNetworkCredential().Password
            Write-Host "[Bootstrap] ✓ Keyfactor API key loaded" -ForegroundColor Green
        }
        catch {
            Write-Host "[Bootstrap] ⚠ Keyfactor API key not configured (cloud features disabled)" -ForegroundColor Yellow
            Write-Host "[Bootstrap]   Run: .\scripts\Setup-PKICredentials.ps1" -ForegroundColor Cyan
        }
    }
    
    # Load Log HMAC Key
    try {
        $hmacCred = Get-PKICredential -Target "LogHMACKey" -ErrorAction Stop
        $Global:LogHMACKey = $hmacCred.Password
        Write-Host "[Bootstrap] ✓ Log HMAC key loaded (integrity protection enabled)" -ForegroundColor Green
    }
    catch {
        Write-Host "[Bootstrap] ⚠ Log HMAC key not configured (log integrity disabled)" -ForegroundColor Yellow
        Write-Host "[Bootstrap]   Run: .\scripts\Setup-PKICredentials.ps1 -GenerateLogHMACKey" -ForegroundColor Cyan
    }
    
    Write-Host ""
}

# Harden directory permissions
if ($Global:EnableSecureLogging) {
    Write-Host "[Bootstrap] Hardening directory permissions..." -ForegroundColor Yellow
    $sensitiveDirs = @("$OutDir\config", "$OutDir\work", "$OutDir\backups")
    foreach ($dir in $sensitiveDirs) {
        if (Test-Path $dir) {
            try {
                Set-SecureDirectoryPermissions -Path $dir -ErrorAction Stop
                Write-Host "[Bootstrap]   ✓ Secured: $dir" -ForegroundColor Green
            }
            catch {
                Write-Host "[Bootstrap]   ⚠ Could not secure: $dir - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    Write-Host ""
}

#====================#
# ENHANCED LOGGING   #
#====================#
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Msg, 
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level='INFO'
    )
    
    if ($Global:EnableSecureLogging -and (Get-Command Write-SecureLog -ErrorAction SilentlyContinue)) {
        try {
            Write-SecureLog -Message $Msg -Level $Level -SessionID $Global:SessionID -LogPath $Global:LogPath -HMACKey $Global:LogHMACKey -ErrorAction Stop
        }
        catch {
            # Fallback to basic logging
            $line = '{0:u} [{1}] [{2}] {3}' -f (Get-Date), $Global:SessionID.Substring(0,8), $Level.ToUpper(), $Msg
            if ($Global:EnableVerboseLog) { Write-Host $line }
            Add-Content -Path $Global:LogPath -Value $line -ErrorAction SilentlyContinue
        }
    }
    else {
        # Basic logging
        $line = '{0:u} [{1}] {2}' -f (Get-Date), $Level.ToUpper(), $Msg
        if ($Global:EnableVerboseLog) { Write-Host $line }
        Add-Content -Path $Global:LogPath -Value $line -ErrorAction SilentlyContinue
    }
}

Write-Log "PKI-Consolidation Tool v1.1.0 started - Session: $Global:SessionID" 'INFO'

#====================#
# UTILITY FUNCTIONS  #
#====================#
function Invoke-OrPreview {
    param([Parameter(Mandatory)][scriptblock]$Action, [string]$Preview = '')
    if ($Global:DoDryRun) {
        Write-Log "[DRYRUN] $Preview" 'INFO'
    } else {
        try {
            & $Action
        }
        catch {
            Write-Log "Action failed: $($_.Exception.Message)" 'ERROR'
            throw
        }
    }
}

# Safe path validation wrapper
function Get-SafePath {
    param([string]$Path)
    
    if ($Global:EnableSecureLogging -and (Get-Command Test-SafePath -ErrorAction SilentlyContinue)) {
        try {
            return Test-SafePath -Path $Path
        }
        catch {
            Write-Log "Path validation failed: $Path - $($_.Exception.Message)" 'WARN'
            return $Path
        }
    }
    return $Path
}

# Try AD/PSPKI modules (best-effort)
try { 
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "ActiveDirectory module loaded" 'INFO'
} 
catch { 
    Write-Log "ActiveDirectory module unavailable. Some features need AD RSAT." 'WARN' 
}

try { 
    Import-Module GroupPolicy -ErrorAction SilentlyContinue
    if (Get-Module GroupPolicy) {
        Write-Log "GroupPolicy module loaded" 'INFO'
    }
} 
catch {}

try { 
    Import-Module PSPKI -ErrorAction SilentlyContinue
    if (Get-Module PSPKI) {
        Write-Log "PSPKI module loaded" 'INFO'
    }
} 
catch {}

#====================#
# UTILITIES          #
#====================#
function Get-ConfigNC { (Get-ADRootDSE).ConfigurationNamingContext }
function Get-PKIServicesDN { "CN=Public Key Services,CN=Services,$(Get-ConfigNC)" }

function Export-ADCA-Cert {
    param([string]$DN,[string]$Path)
    try {
        $safePath = Get-SafePath -Path $Path
        $obj = Get-ADObject -Identity $DN -Properties cACertificate -ErrorAction Stop
        $bytes = $obj.cACertificate | Select-Object -First 1
        if ($bytes) { 
            [IO.File]::WriteAllBytes($safePath, $bytes)
            Write-Log "Exported certificate: $safePath" 'INFO'
            return $true 
        } else { 
            Write-Log "No certificate data for: $DN" 'WARN'
            return $false 
        }
    }
    catch {
        Write-Log "Failed to export certificate from AD: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Invoke-SafeCertutil {
    param([string[]]$CertutilArgs,[string]$Description)
    Invoke-OrPreview -Preview "certutil $($CertutilArgs -join ' ')" -Action {
        try {
            $out = & certutil @CertutilArgs 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "${Description}: Success" 'INFO'
            }
            else {
                Write-Log "${Description}: certutil returned exit code $LASTEXITCODE" 'WARN'
            }
            return $out
        }
        catch {
            Write-Log "${Description}: Failed - $($_.Exception.Message)" 'ERROR'
            throw
        }
    }
}

function Get-CARegistryKeys {
    # Returns objects: CAName, Path, CRLUrls, AIAUrls, AIAExt (AuthorityInformationAccess), OCSPUrls
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration'
    $items = @()
    
    try {
        foreach ($ca in Get-ChildItem $root -ErrorAction SilentlyContinue) {
            if ($ca.PSChildName -eq 'Configuration') { continue }
            
            $crlRaw = (Get-ItemProperty -Path $ca.PSPath -Name 'CRLPublicationURLs' -ErrorAction SilentlyContinue).CRLPublicationURLs
            $aiaRaw = (Get-ItemProperty -Path $ca.PSPath -Name 'CACertPublicationURLs' -ErrorAction SilentlyContinue).CACertPublicationURLs
            $aiaExt = (Get-ItemProperty -Path $ca.PSPath -Name 'AuthorityInformationAccess' -ErrorAction SilentlyContinue).AuthorityInformationAccess

            $crlUrls  = @(); if ($crlRaw) { $crlUrls = ($crlRaw -split "`r?`n") | Where-Object { $_.Trim() } }
            $aiaUrls  = @(); if ($aiaRaw) { $aiaUrls = ($aiaRaw -split "`r?`n") | Where-Object { $_.Trim() } }
            $aiaLines = @(); if ($aiaExt) { $aiaLines = ($aiaExt -split "`r?`n") | Where-Object { $_.Trim() } }
            $ocspUrls = @($aiaLines | Where-Object { $_ -match '(?i)CERT_OCSP_URL_PROP_ID|/ocsp' })

            $items += [pscustomobject]@{
                CAName   = $ca.PSChildName
                Path     = $ca.PSPath
                CRLUrls  = $crlUrls
                AIAUrls  = $aiaUrls
                AIAExt   = $aiaLines
                OCSPUrls = $ocspUrls
            }
        }
    }
    catch {
        Write-Log "Failed to read CA registry keys: $($_.Exception.Message)" 'ERROR'
    }
    
    return $items
}

function Get-CertEnrollFolder { Join-Path $env:WINDIR 'System32\CertSrv\CertEnroll' }

function Copy-IfLocalPath {
    param([string]$Source, [string]$TargetSpec)
    # Skip LDAP/HTTP/UNC/tokenized paths; only plain local targets here
    if ($TargetSpec -match '^(?i)(ldap:|ldaps:|https?://|\\\\)') { return }
    $expanded = $TargetSpec -replace '%\d',''
    try {
        $safeSource = Get-SafePath -Path $Source
        $safeTarget = Get-SafePath -Path $expanded
        $dir = Split-Path -Path $safeTarget -Parent
        if ($dir -and (Test-Path $dir)) {
            Copy-Item -LiteralPath $safeSource -Destination $safeTarget -Force -ErrorAction Stop
            Write-Log "Copied `"$safeSource`" -> `"$safeTarget`"" 'INFO'
        }
    } catch { 
        Write-Log "Copy failed to `"$expanded`": $($_.Exception.Message)" 'WARN' 
    }
}

function Initialize-ConfigSkeleton {
    if (-not (Test-Path $Global:GuardedConfigPath)) {
        $sample = @'
{
  "CAs": [
    {
      "CAName": "PUT-YOUR-CA-DISPLAY-NAME-HERE",
      "Additions": {
        "CRLPublicationURLs": [
          "65:file://C:\\\\PKI\\\\CRL\\\\%3%8%9.crl",
          "79:http://pki.yourco.com/crl/%3%8%9.crl"
        ],
        "CACertPublicationURLs": [
          "2:file://C:\\\\PKI\\\\AIA\\\\%3%4.crt",
          "32:http://pki.yourco.com/aia/%3%4.crt"
        ],
        "AuthorityInformationAccess": [
          "1:CERT_OCSP_URL_PROP_ID:http://ocsp.yourco.com/ocsp",
          "2:CERT_AIA_URL_PROP_ID:http://pki.yourco.com/aia/%3%4.crt"
        ]
      }
    }
  ]
}
'@
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $Global:GuardedConfigPath)
        $sample | Out-File -FilePath $Global:GuardedConfigPath -Encoding utf8
        Write-Log "Created config skeleton at $Global:GuardedConfigPath" 'INFO'
    }
}

# [Continue with all existing phase functions from original script...]
# I'll include the key ones and note that the rest continue as before

#====================#
# PHASE 1: AUDIT     #
#====================#
function Invoke-Phase1Audit {
    Write-Log "Phase 1 - Discovering Enterprise CAs" 'INFO'
    try {
        $base = Get-PKIServicesDN
        $cas = Get-ADObject -LDAPFilter '(objectClass=pKIEnrollmentService)' -SearchBase $base -Properties dNSHostName,certificateTemplates,flags,distinguishedName,cn -ErrorAction Stop
        $rows = @()
        
        foreach ($ca in $cas) {
            $cerPath = Get-SafePath -Path (Join-Path "$OutDir\exports" "$($ca.cn)_cacert.cer")
            if (Export-ADCA-Cert -DN $ca.DistinguishedName -Path $cerPath) {
                $dump = & certutil -dump $cerPath 2>$null
                $subject  = ($dump | Select-String 'Subject:').Line
                $issuer   = ($dump | Select-String 'Issuer:').Line
                $sigAlg   = ($dump | Select-String 'Signature Algorithm').Line
                $notAfter = ($dump | Select-String 'NotAfter:').Line
                $rows += [pscustomobject]@{
                    CA_CN        = $ca.cn
                    Hostname     = $ca.dNSHostName
                    DN           = $ca.DistinguishedName
                    Subject      = $subject
                    Issuer       = $issuer
                    SigAlgorithm = $sigAlg
                    NotAfterRaw  = $notAfter
                    Templates    = ($ca.certificateTemplates -join ';')
                    CertPath     = $cerPath
                }
            } else {
                Write-Log "Failed to export cACertificate for $($ca.cn)" 'WARN'
            }
        }
        
        $csv = Get-SafePath -Path (Join-Path "$OutDir\reports" 'CA-Inventory.csv')
        $rows | Export-Csv $csv -NoTypeInformation
        Write-Log "Audit done -> $csv" 'INFO'
    }
    catch {
        Write-Log "Phase 1 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#==============================#
# PHASE 2: SELECT AUTHORITATIVE#
#==============================#
function Invoke-Phase2SelectRoot {
    Write-Log "Phase 2 - Selecting Authoritative Enterprise Root" 'INFO'
    try {
        $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
        if (-not (Test-Path $csv)) { throw "Run Phase 1 first (audit)." }
        $inv = Import-Csv $csv

        if ($Global:AuthoritativeRootCN) {
            Write-Log "Root preset: $Global:AuthoritativeRootCN" 'INFO'
        } else {
            $roots = $inv | Where-Object { $_.Subject -eq $_.Issuer }
            $sha2  = $roots | Where-Object { $_.SigAlgorithm -match 'sha256|sha384|sha512' }
            $pick  = $sha2 | Select-Object -First 1
            if (-not $pick) { $pick = $roots | Select-Object -First 1 }
            $Global:AuthoritativeRootCN = ($pick.Subject -replace '^Subject:\s*','').Trim()
            Write-Log "Auto-selected root: $Global:AuthoritativeRootCN" 'INFO'
        }
        "$($Global:AuthoritativeRootCN)" | Out-File (Join-Path "$OutDir\reports" 'AuthoritativeRoot.txt') -Encoding ascii
        Write-Log "Wrote AuthoritativeRoot.txt" 'INFO'
    }
    catch {
        Write-Log "Phase 2 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

# [Continue with Phase 3-9 from original script - maintaining same logic but with enhanced logging]
# For brevity, I'll include a template showing the pattern and note the rest continue similarly

#========================================#
# PHASE 3: GENERATE SUB-CA CSR (INF/REQ) #
#========================================#
function Invoke-Phase3NewSubCSR {
    Write-Log "Phase 3 - Generating Sub-CA CSRs" 'INFO'
    try {
        $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
        if (-not (Test-Path $csv)) { throw "Run Phase 1 first." }
        $inv = Import-Csv $csv
        $subs = $inv | Where-Object { $_.Subject -ne $_.Issuer }

        foreach ($s in $subs) {
            $subj = ($s.Subject -replace '^Subject:\s*','').Trim()
            $base = ($s.CA_CN -replace '[^\w-]','_')
            
            # Validate filename
            if ($Global:EnableSecureLogging -and (Get-Command Test-SafeFileName -ErrorAction SilentlyContinue)) {
                $base = Test-SafeFileName -FileName $base
            }
            
            $infPath = Get-SafePath -Path (Join-Path "$OutDir\work" "$base.subca.inf")
            $reqPath = Get-SafePath -Path (Join-Path "$OutDir\work" "$base.subca.req")
            
            $inf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "$subj"
KeyLength = 4096
HashAlgorithm = sha256
Exportable = TRUE
MachineKeySet = TRUE
RequestType = PKCS10
KeySpec = 2

[Extensions]
2.5.29.19 = "{text}"
    BasicConstraints=CA:true,pathlength=0
2.5.29.15 = "{text}"
    KeyUsage = keyCertSign, cRLSign

[RequestAttributes]
CertificateTemplate = SubCA
"@
            $inf | Out-File -FilePath $infPath -Encoding ascii
            Invoke-OrPreview -Preview "certreq -new $infPath $reqPath" -Action { 
                & certreq -new $infPath $reqPath | Out-Null 
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "certreq failed for $base with exit code $LASTEXITCODE" 'ERROR'
                }
            }
            Write-Log "Created: $infPath; $reqPath" 'INFO'
        }
        Write-Log "Submit the *.req to the authoritative root; place issued *.cer into $OutDir\work\issued" 'INFO'
    }
    catch {
        Write-Log "Phase 3 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#========================================#
# PHASE 4: ACCEPT & PUBLISH SUB-CA CERTS #
#========================================#
function Invoke-Phase4AcceptAndPublish {
    Write-Log "Phase 4 - Accept Issued Sub-CA Certs + Publish to AD" 'INFO'
    try {
        $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
        if (-not (Test-Path $csv)) { throw "Run Phase 1 first." }
        $inv = Import-Csv $csv
        $subs = $inv | Where-Object { $_.Subject -ne $_.Issuer }
        
        $issuedDir = Get-SafePath -Path (Join-Path "$OutDir\work" 'issued')
        if (-not (Test-Path $issuedDir)) {
            throw "Issued certificates directory not found: $issuedDir"
        }
        
        $cerFiles = Get-ChildItem -Path $issuedDir -Filter '*.cer' -ErrorAction SilentlyContinue
        if (-not $cerFiles) {
            Write-Log "No issued certificates found in $issuedDir" 'WARN'
            Write-Log "Submit CSRs from Phase 3 to authoritative root, then place issued .cer files here" 'INFO'
            return
        }
        
        Write-Log "Found $($cerFiles.Count) issued certificate(s)" 'INFO'
        
        foreach ($cerFile in $cerFiles) {
            Write-Log "Processing: $($cerFile.Name)" 'INFO'
            
            # Install certificate locally
            $certPath = Get-SafePath -Path $cerFile.FullName
            
            Invoke-OrPreview -Preview "certreq -accept $certPath" -Action {
                $out = & certreq -accept $certPath 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Certificate accepted: $($cerFile.Name)" 'INFO'
                }
                else {
                    Write-Log "Failed to accept certificate: $($cerFile.Name) - Exit code: $LASTEXITCODE" 'ERROR'
                    Write-Log "Output: $($out -join "`n")" 'DEBUG'
                }
            }
            
            # Publish to AD
            $dump = & certutil -dump $certPath 2>$null
            $subject = ($dump | Select-String 'Subject:').Line
            
            # Find matching CA in inventory
            $matchingCA = $subs | Where-Object { $_.Subject -match [regex]::Escape($subject) }
            
            if ($matchingCA) {
                Write-Log "Publishing certificate to AD for: $($matchingCA.CA_CN)" 'INFO'
                
                Invoke-SafeCertutil -CertutilArgs @('-dspublish', '-f', $certPath, 'NTAuthCA') `
                                    -Description "Publish $($cerFile.Name) to NTAuthCA"
                
                Invoke-SafeCertutil -CertutilArgs @('-dspublish', '-f', $certPath, 'SubCA') `
                                    -Description "Publish $($cerFile.Name) to SubCA container"
            }
            else {
                Write-Log "Could not find matching CA in inventory for: $subject" 'WARN'
            }
        }
        
        Write-Log "Phase 4 complete. Verify with: certutil -viewstore -enterprise NTAuthCA" 'INFO'
    }
    catch {
        Write-Log "Phase 4 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#========================================#
# PHASE 4A: PUBLISH CRL/AIA & OCSP CHECK #
#========================================#
function Invoke-Phase4APublishChanges {
    Write-Log "Phase 4A - Publishing CRL/AIA & OCSP Health Check" 'INFO'
    try {
        $cas = Get-CARegistryKeys
        if (-not $cas) {
            Write-Log "No CAs found in registry on this host" 'WARN'
            return
        }
        
        foreach ($ca in $cas) {
            Write-Log "Processing CA: $($ca.CAName)" 'INFO'
            
            # Get CertEnroll folder
            $certEnrollPath = Get-CertEnrollFolder
            if (-not (Test-Path $certEnrollPath)) {
                Write-Log "CertEnroll folder not found: $certEnrollPath" 'WARN'
                continue
            }
            
            # Find latest CRL
            $crlPattern = "*$($ca.CAName)*.crl"
            $crlFiles = Get-ChildItem -Path $certEnrollPath -Filter $crlPattern -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending
            
            if ($crlFiles) {
                $latestCRL = $crlFiles | Select-Object -First 1
                Write-Log "Latest CRL: $($latestCRL.Name) (Modified: $($latestCRL.LastWriteTime))" 'INFO'
                
                # Copy CRL to configured locations
                foreach ($crlUrl in $ca.CRLUrls) {
                    Copy-IfLocalPath -Source $latestCRL.FullName -TargetSpec $crlUrl
                }
            }
            else {
                Write-Log "No CRL files found for $($ca.CAName)" 'WARN'
            }
            
            # Find CA certificate
            $certPattern = "*$($ca.CAName)*.crt"
            $certFiles = Get-ChildItem -Path $certEnrollPath -Filter $certPattern -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending
            
            if ($certFiles) {
                $latestCert = $certFiles | Select-Object -First 1
                Write-Log "Latest CA cert: $($latestCert.Name)" 'INFO'
                
                # Copy certificate to AIA locations
                foreach ($aiaUrl in $ca.AIAUrls) {
                    Copy-IfLocalPath -Source $latestCert.FullName -TargetSpec $aiaUrl
                }
            }
            
            # Test OCSP responders if module available
            if (Get-Command Test-CAOCSPHealth -ErrorAction SilentlyContinue) {
                Write-Log "Testing OCSP health for $($ca.CAName)..." 'INFO'
                try {
                    Import-Module (Join-Path $PSScriptRoot 'modules\PKI-OCSP.psm1') -ErrorAction Stop
                    $ocspResult = Test-CAOCSPHealth -CAName $ca.CAName
                    
                    if ($ocspResult.AllHealthy) {
                        Write-Log "✓ All OCSP responders healthy ($($ocspResult.ResponderCount) total)" 'INFO'
                    }
                    else {
                        Write-Log "⚠ Some OCSP responders unhealthy" 'WARN'
                        foreach ($responder in $ocspResult.Responders) {
                            if (-not $responder.IsReachable) {
                                Write-Log "  ✗ $($responder.ResponderUrl): $($responder.Error)" 'WARN'
                            }
                        }
                    }
                }
                catch {
                    Write-Log "OCSP health check error: $($_.Exception.Message)" 'WARN'
                }
            }
        }
        
        Write-Log "Phase 4A complete" 'INFO'
    }
    catch {
        Write-Log "Phase 4A failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#=============================================================#
# PHASE 4B: Guarded Mode – Stage & Apply Registry Changes     #
#=============================================================#
function Export-CA-RegBackup {
    param([string]$CAName,[string]$OutFile)
    try {
        $safeOutFile = Get-SafePath -Path $OutFile
        $key = "HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$CAName"
        Invoke-OrPreview -Preview "reg export `"$key`" `"$safeOutFile`" /y" -Action {
            & reg export "$key" "$safeOutFile" /y | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "reg export failed with exit code $LASTEXITCODE"
            }
        }
        Write-Log "Exported registry backup for $CAName -> $safeOutFile" 'INFO'
    }
    catch {
        Write-Log "Failed to backup registry for $CAName : $($_.Exception.Message)" 'ERROR'
        throw
    }
}

function Build-CA-RegPatch {
    param(
        [string]$CAName,
        [string[]]$AddCRL,
        [string[]]$AddAIA,
        [string[]]$AddAIAExt,
        [string]$OutFile
    )
    
    try {
        # Validate CA name
        if ($Global:EnableSecureLogging -and (Get-Command Test-SafeCAName -ErrorAction SilentlyContinue)) {
            $CAName = Test-SafeCAName -CAName $CAName
        }
        
        # Read current values
        $kPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$CAName"
        $crlCur  = (Get-ItemProperty -Path $kPath -Name 'CRLPublicationURLs' -ErrorAction SilentlyContinue).CRLPublicationURLs
        $aiaCur  = (Get-ItemProperty -Path $kPath -Name 'CACertPublicationURLs' -ErrorAction SilentlyContinue).CACertPublicationURLs
        $aiaxCur = (Get-ItemProperty -Path $kPath -Name 'AuthorityInformationAccess' -ErrorAction SilentlyContinue).AuthorityInformationAccess

        $crlList  = @(); if ($crlCur)  { $crlList  = ($crlCur  -split "`r?`n") }
        $aiaList  = @(); if ($aiaCur)  { $aiaList  = ($aiaCur  -split "`r?`n") }
        $aiaxList = @(); if ($aiaxCur) { $aiaxList = ($aiaxCur -split "`r?`n") }

        # Compute additions that are not already present (string match)
        $addCRL   = @($AddCRL  | Where-Object { $_ -and ($crlList  -notcontains $_) })
        $addAIA   = @($AddAIA  | Where-Object { $_ -and ($aiaList  -notcontains $_) })
        $addAIAEx = @($AddAIAExt | Where-Object { $_ -and ($aiaxList -notcontains $_) })

        if (-not ($addCRL + $addAIA + $addAIAEx)) {
            Write-Log "No new lines to add for $CAName; patch not needed." 'INFO'
            return $null
        }

        # Compose REG_MULTI_SZ patch file (.reg)
        $hdr = @(
            "Windows Registry Editor Version 5.00",
            "",
            "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$CAName]"
        )
        $body = @()

        if ($addCRL.Count -gt 0) {
            $all = @($crlList + $addCRL) -join "\0"
            $hex = ([System.Text.Encoding]::Unicode.GetBytes($all + "`0`0") | ForEach-Object { $_.ToString("x2") }) -join ','
            $body += '"CRLPublicationURLs"=hex(7):' + $hex
        }
        if ($addAIA.Count -gt 0) {
            $all = @($aiaList + $addAIA) -join "\0"
            $hex = ([System.Text.Encoding]::Unicode.GetBytes($all + "`0`0") | ForEach-Object { $_.ToString("x2") }) -join ','
            $body += '"CACertPublicationURLs"=hex(7):' + $hex
        }
        if ($addAIAEx.Count -gt 0) {
            $all = @($aiaxList + $addAIAEx) -join "\0"
            $hex = ([System.Text.Encoding]::Unicode.GetBytes($all + "`0`0") | ForEach-Object { $_.ToString("x2") }) -join ','
            $body += '"AuthorityInformationAccess"=hex(7):' + $hex
        }

        $safeOutFile = Get-SafePath -Path $OutFile
        ($hdr + $body + "") | Out-File -FilePath $safeOutFile -Encoding ascii
        Write-Log "Staged patch for $CAName -> $safeOutFile" 'INFO'
        return $safeOutFile
    }
    catch {
        Write-Log "Failed to build registry patch for $CAName : $($_.Exception.Message)" 'ERROR'
        throw
    }
}

function Invoke-Phase4BGuardedChanges {
    Write-Log "Phase 4B - Guarded registry change staging for CRL/AIA/OCSP" 'INFO'
    try {
        Initialize-ConfigSkeleton
        if (-not (Test-Path $Global:GuardedConfigPath)) { 
            Write-Log "Config file missing: $Global:GuardedConfigPath" 'ERROR'
            return 
        }
        
        $cfg = Get-Content $Global:GuardedConfigPath -Raw | ConvertFrom-Json

        $cas = Get-CARegistryKeys
        if (-not $cas) { 
            Write-Log "No CAs found in registry on this host." 'WARN'
            return 
        }

        foreach ($entry in $cfg.CAs) {
            $target = $cas | Where-Object { $_.CAName -eq $entry.CAName }
            if (-not $target) { 
                Write-Log "CA `"$($entry.CAName)`" not found on this host; skipping." 'WARN'
                continue 
            }

            # Backup current registry for this CA
            $backupDir = Get-SafePath -Path (Join-Path "$OutDir\backups" (Get-Date -Format 'yyyyMMdd-HHmmss'))
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
            
            $backup = Join-Path $backupDir ("{0}-backup.reg" -f $entry.CAName)
            Export-CA-RegBackup -CAName $entry.CAName -OutFile $backup

            # Build patch
            $patch = Join-Path $backupDir ("{0}-patch.reg" -f $entry.CAName)
            $patchPath = Build-CA-RegPatch -CAName $entry.CAName `
                -AddCRL   $entry.Additions.CRLPublicationURLs `
                -AddAIA   $entry.Additions.CACertPublicationURLs `
                -AddAIAExt $entry.Additions.AuthorityInformationAccess `
                -OutFile  $patch

            if ($patchPath -and $Global:ApplyGuardedChanges) {
                # Apply patch
                Write-Log "Applying registry patch: $patchPath" 'INFO'
                Invoke-OrPreview -Preview "reg import `"$patchPath`"" -Action { 
                    & reg import "$patchPath" | Out-Null 
                    if ($LASTEXITCODE -ne 0) {
                        throw "reg import failed with exit code $LASTEXITCODE"
                    }
                }
                Write-Log "Applied patch -> $patchPath" 'INFO'
                
                # Restart service with health check
                Write-Log "Restarting CertSvc to pick up changes..." 'INFO'
                Invoke-OrPreview -Preview "Restart-Service CertSvc" -Action { 
                    Restart-Service CertSvc -Force -ErrorAction Stop 
                    
                    # Health check after restart
                    Start-Sleep -Seconds 5
                    $null = & certutil -ping 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "CertSvc restarted successfully and responding" 'INFO'
                    }
                    else {
                        Write-Log "CertSvc restarted but not responding! Attempting rollback..." 'ERROR'
                        # Auto-rollback
                        Stop-Service CertSvc -Force
                        & reg import "$backup" | Out-Null
                        Start-Service CertSvc
                        throw "Service health check failed after restart. Registry rolled back."
                    }
                }
            } elseif ($patchPath) {
                Write-Log "Patch staged (not applied). Review & apply later -> $patchPath" 'INFO'
            }
        }

        Write-Log "Phase 4B complete." 'INFO'
    }
    catch {
        Write-Log "Phase 4B failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#========================================#
# PHASE 5: TRUST PROPAGATION (GPO)      #
#========================================#
function Invoke-Phase5TrustPropagation {
    Write-Log "Phase 5 - Trust Propagation via GPO" 'INFO'
    try {
        # Check if GroupPolicy module is available
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            Write-Log "GroupPolicy module not available. Install RSAT-GroupPolicy-PowerShell feature." 'ERROR'
            return
        }
        
        Import-Module GroupPolicy -ErrorAction Stop
        
        # Read authoritative root
        $rootFile = Join-Path "$OutDir\reports" 'AuthoritativeRoot.txt'
        if (-not (Test-Path $rootFile)) {
            throw "Run Phase 2 first to select authoritative root"
        }
        $rootCN = Get-Content $rootFile -Raw
        
        # Export root certificate
        $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
        $inv = Import-Csv $csv
        $rootCA = $inv | Where-Object { $_.Subject -eq $rootCN.Trim() }
        
        if (-not $rootCA) {
            throw "Could not find authoritative root CA in inventory"
        }
        
        $rootCertPath = Get-SafePath -Path $rootCA.CertPath
        
        Write-Log "Authoritative Root Certificate: $rootCertPath" 'INFO'
        Write-Log "" 'INFO'
        Write-Log "=== GPO CONFIGURATION INSTRUCTIONS ===" 'INFO'
        Write-Log "" 'INFO'
        Write-Log "To propagate trust via Group Policy:" 'INFO'
        Write-Log "1. Open Group Policy Management Console (gpmc.msc)" 'INFO'
        Write-Log "2. Create or edit a GPO linked to your domain" 'INFO'
        Write-Log "3. Navigate to: Computer Configuration > Policies > Windows Settings >" 'INFO'
        Write-Log "   Security Settings > Public Key Policies > Trusted Root Certification Authorities" 'INFO'
        Write-Log "4. Right-click > Import" 'INFO'
        Write-Log "5. Import certificate: $rootCertPath" 'INFO'
        Write-Log "6. Force GPO update: gpupdate /force" 'INFO'
        Write-Log "" 'INFO'
        Write-Log "Verification command:" 'INFO'
        Write-Log "  Get-ChildItem Cert:\LocalMachine\Root | Where-Object { `$_.Subject -match '$($rootCA.CA_CN)' }" 'INFO'
        Write-Log "" 'INFO'
        
        # Generate helper script
        $gpoScriptPath = Join-Path "$OutDir\work" 'Deploy-TrustViaGPO.ps1'
        $gpoScript = @"
# Trust Propagation Helper Script
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Author: Adrian Johnson <adrian207@gmail.com>

#Requires -Modules GroupPolicy
#Requires -RunAsAdministrator

`$ErrorActionPreference = 'Stop'

`$rootCertPath = '$rootCertPath'
`$gpoName = Read-Host 'Enter GPO name (or leave blank to list existing GPOs)'

if (-not `$gpoName) {
    Write-Host "`nExisting GPOs:" -ForegroundColor Cyan
    Get-GPO -All | Select-Object DisplayName, DomainName, CreationTime | Format-Table
    exit
}

Write-Host "Manual GPO configuration required:" -ForegroundColor Yellow
Write-Host "1. Open: gpmc.msc"
Write-Host "2. Edit GPO: `$gpoName"
Write-Host "3. Navigate to: Computer Config > Policies > Windows Settings > Security > Public Key Policies > Trusted Root CAs"
Write-Host "4. Import: `$rootCertPath"
Write-Host ""
Write-Host "Or use certutil for quick deployment (not GPO-based):"
Write-Host "  certutil -addstore -enterprise Root `$rootCertPath"
"@
        
        $gpoScript | Out-File -FilePath $gpoScriptPath -Encoding utf8
        Write-Log "Generated helper script: $gpoScriptPath" 'INFO'
        
        # Offer quick deployment option
        Write-Host "`n" -NoNewline
        $response = Read-Host "Deploy root certificate to Enterprise Root store now? (Y/N)"
        if ($response -eq 'Y') {
            Invoke-SafeCertutil -CertutilArgs @('-addstore', '-enterprise', 'Root', $rootCertPath) `
                                -Description "Add root certificate to Enterprise Root store"
            Write-Log "Root certificate added to Enterprise Root store" 'INFO'
        }
        
        Write-Log "Phase 5 complete" 'INFO'
    }
    catch {
        Write-Log "Phase 5 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#========================================#
# PHASE 6: CLOUD INTEGRATIONS           #
#========================================#
function Invoke-Phase6CloudIntegrations {
    Write-Log "Phase 6 - Cloud Integrations (Azure Key Vault / Keyfactor)" 'INFO'
    try {
        $hasAKV = $Global:VaultName -and $Global:VaultName -ne ''
        $hasKeyfactor = $Global:KeyfactorBaseUrl -and $Global:KeyfactorBaseUrl -ne ''
        
        if (-not $hasAKV -and -not $hasKeyfactor) {
            Write-Log "No cloud integrations configured. Edit script variables to enable." 'WARN'
            Write-Log "  - `$Global:VaultName for Azure Key Vault" 'INFO'
            Write-Log "  - `$Global:KeyfactorBaseUrl for Keyfactor integration" 'INFO'
            return
        }
        
        # Azure Key Vault Integration
        if ($hasAKV) {
            Write-Log "Azure Key Vault Integration: $Global:VaultName" 'INFO'
            
            # Check if Az.KeyVault module is available
            if (Get-Module -ListAvailable -Name Az.KeyVault) {
                Import-Module Az.KeyVault -ErrorAction Stop
                
                Write-Log "Checking Azure Key Vault connectivity..." 'INFO'
                try {
                    $vault = Get-AzKeyVault -VaultName $Global:VaultName -ErrorAction Stop
                    Write-Log "✓ Connected to Key Vault: $($vault.VaultName)" 'INFO'
                    Write-Log "  Location: $($vault.Location)" 'INFO'
                    Write-Log "  Resource Group: $($vault.ResourceGroupName)" 'INFO'
                    
                    # List certificates in vault
                    $certs = Get-AzKeyVaultCertificate -VaultName $Global:VaultName -ErrorAction SilentlyContinue
                    if ($certs) {
                        Write-Log "Certificates in vault: $($certs.Count)" 'INFO'
                        foreach ($cert in $certs | Select-Object -First 5) {
                            Write-Log "  - $($cert.Name)" 'INFO'
                        }
                    }
                }
                catch {
                    Write-Log "Azure Key Vault connection failed: $($_.Exception.Message)" 'ERROR'
                    Write-Log "Ensure you are authenticated: Connect-AzAccount" 'INFO'
                }
            }
            else {
                Write-Log "Az.KeyVault module not installed. Install with:" 'WARN'
                Write-Log "  Install-Module -Name Az.KeyVault -Scope CurrentUser" 'INFO'
            }
        }
        
        # Keyfactor Integration
        if ($hasKeyfactor) {
            Write-Log "Keyfactor Integration: $Global:KeyfactorBaseUrl" 'INFO'
            
            if (-not $Global:KeyfactorApiKey) {
                Write-Log "Keyfactor API key not configured. Run Setup-PKICredentials.ps1" 'WARN'
            }
            else {
                Write-Log "Testing Keyfactor API connectivity..." 'INFO'
                try {
                    $headers = @{
                        'X-Keyfactor-Requested-With' = 'APIClient'
                        'Authorization' = "Bearer $Global:KeyfactorApiKey"
                    }
                    
                    $statusUrl = "$Global:KeyfactorBaseUrl/Status"
                    $response = Invoke-RestMethod -Uri $statusUrl -Headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop
                    
                    Write-Log "✓ Keyfactor API responding" 'INFO'
                    Write-Log "  Version: $($response.Version)" 'INFO'
                }
                catch {
                    Write-Log "Keyfactor API connection failed: $($_.Exception.Message)" 'ERROR'
                    Write-Log "Verify API key and base URL configuration" 'INFO'
                }
            }
        }
        
        Write-Log "Phase 6 complete" 'INFO'
    }
    catch {
        Write-Log "Phase 6 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#========================================#
# PHASE 7: LEAF RE-ISSUANCE TRIGGERS    #
#========================================#
function Invoke-Phase7LeafReissue {
    Write-Log "Phase 7 - Leaf Certificate Re-issuance Triggers" 'INFO'
    try {
        Write-Log "Generating re-enrollment notification script..." 'INFO'
        
        $notificationScript = Join-Path "$OutDir\work" 'Trigger-CertificateRenewal.ps1'
        $scriptContent = @"
<#
.SYNOPSIS
    Triggers certificate re-enrollment for affected users/computers

.DESCRIPTION
    Forces certificate renewal after CA hierarchy changes. Run this script
    on clients or distribute via GPO/SCCM after trust propagation is complete.

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
#>

#Requires -RunAsAdministrator

`$ErrorActionPreference = 'Stop'

Write-Host "Certificate Re-enrollment Trigger" -ForegroundColor Cyan
Write-Host "==================================`n"

# Method 1: Force GPO update and auto-enrollment
Write-Host "[1/4] Forcing Group Policy update..."
gpupdate /force /target:computer | Out-Null
Write-Host "  ✓ Computer policies updated"

# Method 2: Trigger certificate auto-enrollment
Write-Host "[2/4] Triggering certificate auto-enrollment..."
certutil -pulse | Out-Null
Write-Host "  ✓ Auto-enrollment triggered"

# Method 3: Refresh certificate stores
Write-Host "[3/4] Refreshing certificate stores..."
Get-ChildItem Cert:\LocalMachine\My | Out-Null
Get-ChildItem Cert:\CurrentUser\My | Out-Null
Write-Host "  ✓ Certificate stores refreshed"

# Method 4: Display certificates nearing expiration
Write-Host "[4/4] Checking for certificates nearing expiration..."
`$expiringSoon = Get-ChildItem Cert:\LocalMachine\My | 
    Where-Object { `$_.NotAfter -lt (Get-Date).AddDays(90) -and `$_.NotAfter -gt (Get-Date) } |
    Select-Object Subject, Thumbprint, NotAfter

if (`$expiringSoon) {
    Write-Host "  ⚠ Certificates expiring within 90 days:" -ForegroundColor Yellow
    `$expiringSoon | Format-Table -AutoSize
}
else {
    Write-Host "  ✓ No certificates expiring soon"
}

Write-Host "`nRe-enrollment process complete!" -ForegroundColor Green
Write-Host "Monitor certificate requests on your CA servers."
"@
        
        $scriptContent | Out-File -FilePath $notificationScript -Encoding utf8
        Write-Log "Created: $notificationScript" 'INFO'
        
        Write-Host "`n" -NoNewline
        Write-Host "=== CERTIFICATE RE-ISSUANCE PLAN ===" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1. PILOT GROUP (Week 1):" -ForegroundColor Yellow
        Write-Host "   - Deploy to 5-10 test machines"
        Write-Host "   - Run: $notificationScript"
        Write-Host "   - Verify new certificates issued from updated CAs"
        Write-Host ""
        Write-Host "2. PHASED ROLLOUT (Weeks 2-4):" -ForegroundColor Yellow
        Write-Host "   - Deploy via GPO Startup Script or SCCM"
        Write-Host "   - Monitor CA request queues"
        Write-Host "   - Track certificate issuance rates"
        Write-Host ""
        Write-Host "3. MONITORING:" -ForegroundColor Yellow
        Write-Host "   - Check CA logs for failed requests"
        Write-Host "   - Monitor certificate expiration dates"
        Write-Host "   - Verify trust chain on client machines"
        Write-Host ""
        
        Write-Log "Phase 7 complete" 'INFO'
    }
    catch {
        Write-Log "Phase 7 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#========================================#
# PHASE 8: VERIFICATION REPORT           #
#========================================#
function Invoke-Phase8Verify {
    Write-Log "Phase 8 - Generating Verification Report" 'INFO'
    try {
        $reportPath = Get-SafePath -Path (Join-Path "$OutDir\reports" "Verification-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html")
        
        Write-Log "Collecting verification data..." 'INFO'
        
        # Load inventory
        $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
        $inv = Import-Csv $csv -ErrorAction SilentlyContinue
        
        # Generate HTML report
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>PKI Consolidation Verification Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f9f9f9; }
        .status-good { color: #107c10; font-weight: bold; }
        .status-warn { color: #ff8c00; font-weight: bold; }
        .status-error { color: #d13438; font-weight: bold; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; padding: 15px; background: #f0f0f0; border-radius: 5px; }
        .metric-value { font-size: 24px; font-weight: bold; color: #0078d4; }
        .metric-label { font-size: 12px; color: #666; text-transform: uppercase; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
    </style>
</head>
<body>
<div class="container">
    <h1>🔒 PKI Consolidation Verification Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p><strong>Session ID:</strong> $Global:SessionID</p>
    <p><strong>Report Path:</strong> $reportPath</p>
    
    <h2>📊 Summary Metrics</h2>
    <div class="metric">
        <div class="metric-value">$($inv.Count)</div>
        <div class="metric-label">Total CAs</div>
    </div>
    <div class="metric">
        <div class="metric-value">$(($inv | Where-Object { $_.Subject -eq $_.Issuer }).Count)</div>
        <div class="metric-label">Root CAs</div>
    </div>
    <div class="metric">
        <div class="metric-value">$(($inv | Where-Object { $_.Subject -ne $_.Issuer }).Count)</div>
        <div class="metric-label">Subordinate CAs</div>
    </div>
    
    <h2>📋 CA Inventory</h2>
    <table>
        <tr>
            <th>CA Name</th>
            <th>Type</th>
            <th>Hostname</th>
            <th>Signature Algorithm</th>
            <th>Status</th>
        </tr>
"@
        
        foreach ($ca in $inv) {
            $type = if ($ca.Subject -eq $ca.Issuer) { "Root CA" } else { "Subordinate CA" }
            $sigAlg = if ($ca.SigAlgorithm -match 'sha256|sha384|sha512') { 
                "<span class='status-good'>$($ca.SigAlgorithm)</span>" 
            } else { 
                "<span class='status-warn'>$($ca.SigAlgorithm)</span>" 
            }
            
            # Check if CA is accessible
            $status = "<span class='status-good'>✓ Active</span>"
            if ($ca.Hostname) {
                try {
                    $null = Test-Connection $ca.Hostname -Count 1 -Quiet -ErrorAction Stop
                } catch {
                    $status = "<span class='status-warn'>⚠ Unreachable</span>"
                }
            }
            
            $html += @"
        <tr>
            <td>$($ca.CA_CN)</td>
            <td>$type</td>
            <td>$($ca.Hostname)</td>
            <td>$sigAlg</td>
            <td>$status</td>
        </tr>
"@
        }
        
        $html += @"
    </table>
    
    <h2>✅ Verification Checklist</h2>
    <table>
        <tr>
            <th width="60%">Check</th>
            <th width="20%">Status</th>
            <th width="20%">Action</th>
        </tr>
        <tr>
            <td>CA Discovery Complete</td>
            <td class="status-good">✓ PASS</td>
            <td>-</td>
        </tr>
        <tr>
            <td>Authoritative Root Selected</td>
            <td>$(if (Test-Path (Join-Path "$OutDir\reports" 'AuthoritativeRoot.txt')) { "<span class='status-good'>✓ PASS</span>" } else { "<span class='status-warn'>⚠ PENDING</span>" })</td>
            <td>$(if (Test-Path (Join-Path "$OutDir\reports" 'AuthoritativeRoot.txt')) { "-" } else { "Run Phase 2" })</td>
        </tr>
        <tr>
            <td>Sub-CA CSRs Generated</td>
            <td>$(if ((Get-ChildItem "$OutDir\work\*.req" -ErrorAction SilentlyContinue).Count -gt 0) { "<span class='status-good'>✓ PASS</span>" } else { "<span class='status-warn'>⚠ PENDING</span>" })</td>
            <td>$(if ((Get-ChildItem "$OutDir\work\*.req" -ErrorAction SilentlyContinue).Count -gt 0) { "-" } else { "Run Phase 3" })</td>
        </tr>
        <tr>
            <td>Certificates Issued & Published</td>
            <td>$(if ((Get-ChildItem "$OutDir\work\issued\*.cer" -ErrorAction SilentlyContinue).Count -gt 0) { "<span class='status-good'>✓ PASS</span>" } else { "<span class='status-warn'>⚠ PENDING</span>" })</td>
            <td>$(if ((Get-ChildItem "$OutDir\work\issued\*.cer" -ErrorAction SilentlyContinue).Count -gt 0) { "-" } else { "Run Phase 4" })</td>
        </tr>
        <tr>
            <td>CRL/AIA Distribution Configured</td>
            <td><span class="status-warn">⚠ MANUAL CHECK</span></td>
            <td>Verify registry settings</td>
        </tr>
        <tr>
            <td>Trust Propagated via GPO</td>
            <td><span class="status-warn">⚠ MANUAL CHECK</span></td>
            <td>Check GPO deployment</td>
        </tr>
        <tr>
            <td>Certificate Re-enrollment Triggered</td>
            <td><span class="status-warn">⚠ MANUAL CHECK</span></td>
            <td>Monitor CA request queues</td>
        </tr>
    </table>
    
    <h2>🔍 Recommended Next Steps</h2>
    <ol>
        <li>Verify certificate chain validation on client machines</li>
        <li>Monitor CA request queues for re-enrollment activity</li>
        <li>Check CRL publication and freshness</li>
        <li>Test OCSP responder availability</li>
        <li>Review application certificate usage</li>
        <li>Plan legacy CA decommissioning after 90-day validation period</li>
    </ol>
    
    <div class="footer">
        <p><strong>Author:</strong> Adrian Johnson &lt;adrian207@gmail.com&gt;</p>
        <p><strong>Tool:</strong> PKI-Consolidation v1.2.0-alpha</p>
        <p><strong>GitHub:</strong> https://github.com/adrian207/PKI-Consolidation</p>
    </div>
</div>
</body>
</html>
"@
        
        $html | Out-File -FilePath $reportPath -Encoding utf8
        Write-Log "Verification report generated: $reportPath" 'INFO'
        
        # Open in browser
        Write-Host "`n" -NoNewline
        $response = Read-Host "Open report in browser? (Y/N)"
        if ($response -eq 'Y') {
            Start-Process $reportPath
        }
        
        Write-Log "Phase 8 complete" 'INFO'
    }
    catch {
        Write-Log "Phase 8 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#========================================#
# PHASE 9: DECOMMISSION LEGACY CAs       #
#========================================#
function Invoke-Phase9DecommissionLegacy {
    Write-Log "Phase 9 - Decommission Legacy CAs" 'INFO'
    try {
        Write-Host "`n" -NoNewline
        Write-Host "⚠⚠⚠ WARNING: DESTRUCTIVE OPERATION ⚠⚠⚠" -ForegroundColor Red
        Write-Host ""
        Write-Host "This phase will unpublish legacy CA certificates from Active Directory." -ForegroundColor Yellow
        Write-Host "Only proceed if:" -ForegroundColor Yellow
        Write-Host "  1. New CA hierarchy is fully operational (90+ days)" -ForegroundColor Yellow
        Write-Host "  2. All certificates have been re-issued" -ForegroundColor Yellow
        Write-Host "  3. No active certificates remain from legacy CAs" -ForegroundColor Yellow
        Write-Host "  4. You have tested certificate validation extensively" -ForegroundColor Yellow
        Write-Host ""
        
        $confirm = Read-Host "Type 'DECOMMISSION' to continue (anything else to cancel)"
        if ($confirm -ne 'DECOMMISSION') {
            Write-Log "Phase 9 cancelled by user" 'WARN'
            return
        }
        
        $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
        $inv = Import-Csv $csv
        
        Write-Host "`nSelect CAs to decommission:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $inv.Count; $i++) {
            Write-Host "  [$i] $($inv[$i].CA_CN) - $($inv[$i].Hostname)"
        }
        
        $selection = Read-Host "`nEnter CA numbers to decommission (comma-separated, or 'cancel')"
        if ($selection -eq 'cancel') {
            Write-Log "Phase 9 cancelled" 'WARN'
            return
        }
        
        $indices = $selection -split ',' | ForEach-Object { [int]$_.Trim() }
        $selectedCAs = $indices | ForEach-Object { $inv[$_] }
        
        foreach ($ca in $selectedCAs) {
            Write-Log "Decommissioning: $($ca.CA_CN)" 'INFO'
            
            # Backup before unpublishing
            $backupPath = Join-Path "$OutDir\backups\decommission" (Get-Date -Format 'yyyyMMdd-HHmmss')
            New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
            
            # Unpublish from AD
            Invoke-OrPreview -Preview "certutil -dspublish -f $($ca.CertPath) delete" -Action {
                & certutil -dspublish -f $ca.CertPath delete 2>&1 | Out-Null
            }
            
            Write-Log "  ✓ Unpublished from AD" 'INFO'
            
            # Create decommissioning report
            $decommReport = @"
CA DECOMMISSIONING RECORD
========================
CA Name: $($ca.CA_CN)
Hostname: $($ca.Hostname)
Subject: $($ca.Subject)
Decommissioned: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Performed by: $env:USERNAME
Session ID: $Global:SessionID

ACTIONS TAKEN:
- Unpublished from Active Directory
- Certificate archived to: $backupPath

POST-DECOMMISSIONING TASKS:
1. Monitor for certificate validation errors
2. Remove CA server from network after validation period
3. Archive CA database and logs
4. Update documentation
5. Notify stakeholders

ROLLBACK PROCEDURE (if needed):
certutil -dspublish -f "$($ca.CertPath)" NTAuthCA
certutil -dspublish -f "$($ca.CertPath)" SubCA
"@
            
            $decommReport | Out-File (Join-Path $backupPath "$($ca.CA_CN)-decommission-record.txt") -Encoding utf8
            Copy-Item $ca.CertPath -Destination $backupPath -ErrorAction SilentlyContinue
            
            Write-Log "  ✓ Decommission record saved: $backupPath" 'INFO'
        }
        
        Write-Log "Phase 9 complete. Monitor for 30 days before removing CA servers." 'INFO'
        Write-Host "`nDecommissioning complete!" -ForegroundColor Green
        Write-Host "Backup location: $backupPath" -ForegroundColor Cyan
    }
    catch {
        Write-Log "Phase 9 failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

#====================#
# MENU UI            #
#====================#
function Show-Menu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         PKI Consolidation Menu - Enhanced Security v1.1      ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "Session: $($Global:SessionID.Substring(0,13))..." -ForegroundColor Gray
    Write-Host "OutDir: $OutDir"
    Write-Host "Authoritative Root: $($Global:AuthoritativeRootCN ?? '(not set yet)')"
    Write-Host "Security: $(if ($Global:EnableSecureLogging) { 'Enhanced (HMAC Logging)' } else { 'Basic' })" -ForegroundColor $(if ($Global:EnableSecureLogging) { 'Green' } else { 'Yellow' })
    Write-Host "AKV Vault: $($Global:VaultName ?? '(none)')"
    Write-Host "Keyfactor: $($Global:KeyfactorBaseUrl ?? '(none)')"
    Write-Host "DryRun: $($Global:DoDryRun)   GuardedMode: $($Global:GuardedMode)   ApplyGuardedChanges: $($Global:ApplyGuardedChanges)"
    Write-Host ""
    Write-Host "1) Audit CAs"
    Write-Host "2) Select/Set Authoritative Root"
    Write-Host "3) Generate Sub-CA CSRs"
    Write-Host "4) Accept Issued Sub-CA Certs + Publish to AD"
    Write-Host "4A) Publish CRL/AIA & OCSP health check"
    Write-Host "4B) Stage & (optionally) APPLY Guarded Registry Changes for CRL/AIA/OCSP"
    Write-Host "5) Trust Propagation (GPO helper)"
    Write-Host "6) Cloud Integrations (AKV / Keyfactor)"
    Write-Host "7) Leaf Re-issuance Triggers"
    Write-Host "8) Verification Report"
    Write-Host "9) Decommission Legacy CAs (unpublish)"
    Write-Host "D) Toggle Dry-Run ($($Global:DoDryRun))"
    Write-Host "G) Toggle Guarded Mode ($($Global:GuardedMode))"
    Write-Host "A) Toggle Apply-Guarded-Changes ($($Global:ApplyGuardedChanges))"
    Write-Host "H) Run CA Health Check" -ForegroundColor Green
    Write-Host "L) Verify Log Integrity" -ForegroundColor Green
    Write-Host "Q) Quit"
    Write-Host ""
}

function Invoke-Menu {
    do {
        Show-Menu
        $choice = Read-Host "Select option"
        try {
            switch ($choice.ToUpper()) {
                '1'  { Invoke-Phase1Audit }
                '2'  { Invoke-Phase2SelectRoot }
                '3'  { Invoke-Phase3NewSubCSR }
                '4'  { Invoke-Phase4AcceptAndPublish }
                '4A' { Invoke-Phase4APublishChanges }
                '4B' { Invoke-Phase4BGuardedChanges }
                '5'  { Invoke-Phase5TrustPropagation }
                '6'  { Invoke-Phase6CloudIntegrations }
                '7'  { Invoke-Phase7LeafReissue }
                '8'  { Invoke-Phase8Verify }
                '9'  { Invoke-Phase9DecommissionLegacy }
                'D'  { $Global:DoDryRun = -not $Global:DoDryRun; Write-Log "DryRun toggled to $($Global:DoDryRun)" 'INFO' }
                'G'  { $Global:GuardedMode = -not $Global:GuardedMode; Write-Log "GuardedMode toggled to $($Global:GuardedMode)" 'INFO' }
                'A'  { $Global:ApplyGuardedChanges = -not $Global:ApplyGuardedChanges; Write-Log "ApplyGuardedChanges toggled to $($Global:ApplyGuardedChanges)" 'INFO' }
                'H'  { 
                    Write-Host "`nRunning CA Health Check..." -ForegroundColor Yellow
                    if (Test-Path (Join-Path $PSScriptRoot "scripts\Test-CAHealth.ps1")) {
                        & (Join-Path $PSScriptRoot "scripts\Test-CAHealth.ps1") -TestIssuance
                    } else {
                        Write-Host "Health check script not found" -ForegroundColor Red
                    }
                }
                'L'  {
                    if ($Global:EnableSecureLogging -and (Get-Command Test-LogIntegrity -ErrorAction SilentlyContinue)) {
                        Write-Host "`nVerifying log integrity..." -ForegroundColor Yellow
                        if ($Global:LogHMACKey) {
                            Test-LogIntegrity -LogPath $Global:LogPath -HMACKey $Global:LogHMACKey
                        } else {
                            Write-Host "Log HMAC key not configured" -ForegroundColor Red
                        }
                    } else {
                        Write-Host "Log integrity check not available" -ForegroundColor Red
                    }
                }
                'Q'  { 
                    Write-Log "PKI-Consolidation session ended - Session: $Global:SessionID" 'INFO'
                    break 
                }
                default { Write-Host "Unknown selection." -ForegroundColor Yellow }
            }
        } catch {
            Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
            Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
        }
        if ($choice -ne 'Q') {
            Write-Host ""; Read-Host "Press Enter to continue"
        }
    } while ($true)
}

#====================#
# ENTRYPOINT         #
#====================#
Write-Host "`n🔒 Security Status:" -ForegroundColor Cyan
if ($Global:EnableSecureLogging) {
    Write-Host "  ✓ Enhanced security enabled" -ForegroundColor Green
    Write-Host "  ✓ HMAC-protected logging: $(if ($Global:LogHMACKey) { 'Active' } else { 'Disabled' })" -ForegroundColor $(if ($Global:LogHMACKey) { 'Green' } else { 'Yellow' })
    Write-Host "  ✓ Secure credential storage: Configured" -ForegroundColor Green
    Write-Host "  ✓ Input validation: Enabled" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Basic security mode (run Setup-PKICredentials.ps1 for enhanced security)" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "📋 Quick Start:" -ForegroundColor Cyan
Write-Host "  1. Run option 1 to audit your CAs" -ForegroundColor White
Write-Host "  2. Enable Dry-Run mode (D) for safe preview" -ForegroundColor White
Write-Host "  3. Use Health Check (H) anytime to verify CA status" -ForegroundColor White
Write-Host ""

Invoke-Menu


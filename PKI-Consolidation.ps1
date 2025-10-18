<# 
PKI-Consolidation.ps1  (with Guarded Mode + CRL/AIA publish + OCSP health)
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
  G) Toggle Guarded Mode (stage-but-don’t-apply changes)
  A) Toggle Apply-Guarded-Changes (apply staged .reg when you choose 4B)
  Q) Quit

Guarded Mode philosophy:
- Detects current CA registry values (CRL/AIA/AIA-OCSP).
- Validates your desired targets from a JSON config (no guessing).
- Writes a versioned .reg patch you can review in Git/Change Mgmt.
- Only applies the patch if you explicitly toggle “Apply Guarded Changes”.

JSON config format (example saved to C:\PKI\Consolidation\config\crl-aia-ocsp.json):
{
  "CAs": [
    {
      "CAName": "Contoso-RootCA",
      "Additions": {
        "CRLPublicationURLs": [
          "65:file://C:\\PKI\\CRL\\%3%8%9.crl",
          "79:http://pki.contoso.com/crl/%3%8%9.crl"
        ],
        "CACertPublicationURLs": [
          "2:file://C:\\PKI\\AIA\\%3%4.crt",
          "32:http://pki.contoso.com/aia/%3%4.crt"
        ],
        "AuthorityInformationAccess": [
          "1:CERT_OCSP_URL_PROP_ID:http://ocsp.contoso.com/ocsp",
          "2:CERT_AIA_URL_PROP_ID:http://pki.contoso.com/aia/%3%4.crt"
        ]
      }
    }
  ]
}

NOTES:
- The numeric prefixes (e.g., 65, 79, 2, 32) are Microsoft’s flag encodings for CA publication behavior.
- Guarded Mode does not invent these; you must provide exact lines you want appended.
- Backups: 4B always exports current CA keys to a dated .reg file before staging a patch.
#>

#====================#
# CONFIG (EDIT ME)   #
#====================#
$Global:OutDir                 = 'C:\PKI\Consolidation'
$Global:AuthoritativeRootCN    = $null   # Example: 'CN=EnterpriseRootCA, O=Contoso, C=US' (else auto-propose)
$Global:VaultName              = ''      # Azure Key Vault name (leave blank to skip)
$Global:KeyfactorBaseUrl       = ''      # e.g. https://kf.yourco.com
$Global:KeyfactorApiKey        = ''      # API bearer token (if used)

# Safety toggles
$Global:DoDryRun               = $false  # Preview actions without executing
$Global:GuardedMode            = $true   # Stage registry changes as a .reg patch (don’t apply unless toggled)
$Global:ApplyGuardedChanges    = $false  # If true, 4B will apply the staged .reg after staging
$Global:EnableVerboseLog       = $true

# Guarded config file (edit or supply your own)
$Global:GuardedConfigPath      = Join-Path $OutDir 'config\crl-aia-ocsp.json'

# Logging
$Global:LogPath                = Join-Path $OutDir 'PKI-Consolidation.log'

#====================#
# BOOTSTRAP          #
#====================#
$ErrorActionPreference = 'Stop'
$null = New-Item -Type Directory -Force -Path $OutDir, "$OutDir\exports", "$OutDir\reports", "$OutDir\work", "$OutDir\work\issued", "$OutDir\config" | Out-Null

function Write-Log {
  param([string]$Msg, [string]$Level='INFO')
  $line = '{0:u} [{1}] {2}' -f (Get-Date), $Level.ToUpper(), $Msg
  if ($Global:EnableVerboseLog) { Write-Host $line }
  Add-Content -Path $Global:LogPath -Value $line
}

function Do-Or-Preview {
  param([Parameter(Mandatory)][scriptblock]$Action, [string]$Preview = '')
  if ($Global:DoDryRun) {
    Write-Log "[DRYRUN] $Preview"
  } else {
    & $Action
  }
}

# Try AD/PSPKI modules (best-effort)
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { Write-Log "ActiveDirectory module unavailable. Some features need AD RSAT." 'WARN' }
try { Import-Module GroupPolicy -ErrorAction SilentlyContinue } catch {}
try { Import-Module PSPKI -ErrorAction SilentlyContinue } catch {}

#====================#
# UTILITIES          #
#====================#
function Get-ConfigNC { (Get-ADRootDSE).ConfigurationNamingContext }
function Get-PKIServicesDN { "CN=Public Key Services,CN=Services,$(Get-ConfigNC)" }

function Export-ADCA-Cert {
  param([string]$DN,[string]$Path)
  $obj = Get-ADObject -Identity $DN -Properties cACertificate
  $bytes = $obj.cACertificate | Select-Object -First 1
  if ($bytes) { [IO.File]::WriteAllBytes($Path, $bytes); return $true } else { return $false }
}

function Safe-Certutil {
  param([string[]]$Args,[string]$Desc)
  Do-Or-Preview -Preview "certutil $($Args -join ' ')" -Action {
    $out = & certutil @Args 2>&1
    Write-Log "$Desc: $($out -join ' ')" 
    return $out
  }
}

function Get-CARegistryKeys {
  # Returns objects: CAName, Path, CRLUrls, AIAUrls, AIAExt (AuthorityInformationAccess), OCSPUrls
  $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration'
  $items = @()
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
  $items
}

function Get-CertEnrollFolder { Join-Path $env:WINDIR 'System32\CertSrv\CertEnroll' }

function Copy-IfLocalPath {
  param([string]$Source, [string]$TargetSpec)
  # Skip LDAP/HTTP/UNC/tokenized paths; only plain local targets here
  if ($TargetSpec -match '^(?i)(ldap:|ldaps:|https?://|\\\\)') { return }
  $expanded = $TargetSpec -replace '%\d',''
  try {
    $dir = Split-Path -Path $expanded -Parent
    if ($dir -and (Test-Path $dir)) {
      Copy-Item -LiteralPath $Source -Destination $expanded -Force -ErrorAction Stop
      Write-Log "Copied `"$Source`" -> `"$expanded`""
    }
  } catch { Write-Log "Copy failed to `"$expanded`": $($_.Exception.Message)" 'WARN' }
}

function Ensure-ConfigSkeleton {
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
    Write-Log "Created config skeleton at $Global:GuardedConfigPath"
  }
}

#====================#
# PHASE 1: AUDIT     #
#====================#
function Phase1-Audit {
  Write-Log "Phase 1 - Discovering Enterprise CAs"
  $base = Get-PKIServicesDN
  $cas = Get-ADObject -LDAPFilter '(objectClass=pKIEnrollmentService)' -SearchBase $base -Properties dNSHostName,certificateTemplates,flags,distinguishedName,cn
  $rows = @()
  foreach ($ca in $cas) {
    $cerPath = Join-Path "$OutDir\exports" "$($ca.cn)_cacert.cer"
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
  $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
  $rows | Export-Csv $csv -NoTypeInformation
  Write-Log "Audit done -> $csv"
}

#==============================#
# PHASE 2: SELECT AUTHORITATIVE#
#==============================#
function Phase2-SelectRoot {
  Write-Log "Phase 2 - Selecting Authoritative Enterprise Root"
  $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
  if (-not (Test-Path $csv)) { throw "Run Phase 1 first (audit)." }
  $inv = Import-Csv $csv

  if ($Global:AuthoritativeRootCN) {
    Write-Log "Root preset: $Global:AuthoritativeRootCN"
  } else {
    $roots = $inv | Where-Object { $_.Subject -eq $_.Issuer }
    $sha2  = $roots | Where-Object { $_.SigAlgorithm -match 'sha256|sha384|sha512' }
    $pick  = $sha2 | Select-Object -First 1
    if (-not $pick) { $pick = $roots | Select-Object -First 1 }
    $Global:AuthoritativeRootCN = ($pick.Subject -replace '^Subject:\s*','').Trim()
    Write-Log "Auto-selected root: $Global:AuthoritativeRootCN"
  }
  "$($Global:AuthoritativeRootCN)" | Out-File (Join-Path "$OutDir\reports" 'AuthoritativeRoot.txt') -Encoding ascii
  Write-Log "Wrote AuthoritativeRoot.txt"
}

#========================================#
# PHASE 3: GENERATE SUB-CA CSR (INF/REQ) #
#========================================#
function Phase3-GenSubCSR {
  Write-Log "Phase 3 - Generating Sub-CA CSRs"
  $csv = Join-Path "$OutDir\reports" 'CA-Inventory.csv'
  if (-not (Test-Path $csv)) { throw "Run Phase 1 first." }
  $inv = Import-Csv $csv
  $subs = $inv | Where-Object { $_.Subject -ne $_.Issuer }

  foreach ($s in $subs) {
    $subj = ($s.Subject -replace '^Subject:\s*','').Trim()
    $base = ($s.CA_CN -replace '[^\w\-]','_')
    $infPath = Join-Path "$OutDir\work" "$base.subca.inf"
    $reqPath = Join-Path "$OutDir\work" "$base.subca.req"
    $inf = @"
[Version]
Signature="$Windows NT$"

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
    Do-Or-Preview -Preview "certreq -new $infPath $reqPath" -Action { & certreq -new $infPath $reqPath | Out-Null }
    Write-Log "Created: $infPath; $reqPath"
  }
  Write-Log "Submit the *.req to the authoritative root; place issued *.cer into $OutDir\work\issued"
}

#=========================================================#
# PHASE 4: ACCEPT SUB-CA CERTS + PUBLISH AD (Root/AIA/NT) #
#=========================================================#
function Phase4-AcceptAndPublish {
  Write-Log "Phase 4 - Accept issued Sub-CA certificates and publish chain to AD"
  $issued = Get-ChildItem "$OutDir\work\issued" -Filter *.cer -File -ErrorAction SilentlyContinue
  if (-not $issued) { Write-Log "No issued sub-CA certs found in $OutDir\work\issued" 'WARN' }

  foreach ($cer in $issued) {
    Do-Or-Preview -Preview "certreq -accept $($cer.FullName)" -Action { & certreq -accept $cer.FullName | Out-Null }
    Write-Log "Accepted sub-CA cert: $($cer.Name)"
  }

  if (-not $Global:AuthoritativeRootCN) { Phase2-SelectRoot }
  $rootCer = Get-ChildItem "$OutDir\exports" -Filter *.cer | Where-Object {
    (Get-Content $_.FullName -Raw) -match ($Global:AuthoritativeRootCN -replace '[\\\^\$\.\|\?\*\+\(\)]','.')
  } | Select-Object -First 1

  if ($rootCer) {
    Safe-Certutil -Args @('-dspublish','-f', $rootCer.FullName, 'RootCA') -Desc 'Publish RootCA to AD'
  } else {
    Write-Log "Authoritative root CER not found in exports; ensure it exists." 'WARN'
  }

  foreach ($cer in $issued) {
    Safe-Certutil -Args @('-dspublish','-f', $cer.FullName, 'SubCA') -Desc "Publish SubCA $($cer.Name) to AD"
  }

  # Ensure NTAuth has issuing CA certs (smartcard logon, etc.)
  $issStore = Get-ChildItem Cert:\LocalMachine\CA -ErrorAction SilentlyContinue
  foreach ($iss in $issStore) {
    $tmp = Join-Path "$OutDir\work" "$($iss.Thumbprint).cer"
    Export-Certificate -Cert $iss -FilePath $tmp | Out-Null
    Safe-Certutil -Args @('-dspublish','-f', $tmp, 'NTAuthCA') -Desc "Publish NTAuthCA for $($iss.Thumbprint)"
  }
  Write-Log "Publication complete."
}

#==============================================#
# PHASE 4A: Publish CRL/AIA & OCSP health      #
#==============================================#
function Phase4A-PublishCRL_AIA_OCSP {
  Write-Log "Phase 4A - Publish CRL/AIA and check OCSP"

  $cas = Get-CARegistryKeys
  if (-not $cas) { Write-Log "No AD CS configuration keys found on this host." 'WARN'; return }

  foreach ($ca in $cas) {
    Write-Log "Processing CA: $($ca.CAName)"

    # Generate fresh CRL
    Do-Or-Preview -Preview "certutil -crl (generate CRL on $($ca.CAName))" -Action { & certutil -crl | Out-Null }

    # Newest CRL in CertEnroll
    $certEnroll = Get-CertEnrollFolder
    $crls = Get-ChildItem $certEnroll -Filter '*.crl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    $latestBase = $crls | Select-Object -First 1
    if ($latestBase) {
      Write-Log "Newest CRL: $($latestBase.FullName)"
      # Publish CRL to AD
      Do-Or-Preview -Preview "certutil -dspublish -f $($latestBase.FullName)" -Action { & certutil -dspublish -f $latestBase.FullName | Out-Null }
      # Copy to any local file targets in CRLPublicationURLs
      foreach ($u in $ca.CRLUrls) { Copy-IfLocalPath -Source $latestBase.FullName -TargetSpec $u }
    } else {
      Write-Log "No CRL files found in $certEnroll" 'WARN'
    }

    # Re-publish issuing CA certs to AD AIA and local file AIA paths
    $caStore = Get-ChildItem Cert:\LocalMachine\CA -ErrorAction SilentlyContinue
    foreach ($iss in $caStore) {
      $tmpCer = Join-Path "$OutDir\work" "$($iss.Thumbprint).cer"
      Export-Certificate -Cert $iss -FilePath $tmpCer | Out-Null
      Safe-Certutil -Args @('-dspublish','-f', $tmpCer, 'SubCA') -Desc "Publish SubCA to AD AIA (idempotent)"
      foreach ($a in $ca.AIAUrls) { Copy-IfLocalPath -Source $tmpCer -TargetSpec $a }
    }

    # OCSP detection & probe
    $hasOcspService = (Get-Service -Name 'OCSPSvc' -ErrorAction SilentlyContinue) -ne $null
    $ocspUrls = $ca.OCSPUrls
    if ($hasOcspService -or ($ocspUrls -and $ocspUrls.Count)) {
      Write-Log "OCSP detected (service: $hasOcspService; urls: $($ocspUrls -join ', '))"
      # Probe endpoints using certutil -urlfetch against an exported cert
      $probeTarget = $latestBase
      if (-not $probeTarget) {
        $leaf = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($leaf) {
          $probeFile = Join-Path "$OutDir\work" "$($leaf.Thumbprint).cer"
          Export-Certificate -Cert $leaf -FilePath $probeFile | Out-Null
          $probeTarget = Get-Item $probeFile
        }
      }
      if ($probeTarget) {
        Do-Or-Preview -Preview "certutil -verify -urlfetch $($probeTarget.FullName)" -Action {
          $vf = & certutil -verify -urlfetch $probeTarget.FullName 2>&1
          Write-Log ("OCSP/URLFetch output (first lines): " + (($vf | Select-Object -First 15) -join ' '))
        }
      } else {
        Write-Log "No suitable certificate found to probe OCSP with certutil -urlfetch." 'WARN'
      }
    } else {
      Write-Log "No OCSP service or AIA OCSP URL detected for $($ca.CAName)."
    }
  }
  Write-Log "Phase 4A complete."
}

#=============================================================#
# PHASE 4B: Guarded Mode – Stage & Apply Registry Changes     #
#=============================================================#
function Export-CA-RegBackup {
  param([string]$CAName,[string]$OutFile)
  $key = "HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$CAName"
  Do-Or-Preview -Preview "reg export `"$key`" `"$OutFile`" /y" -Action {
    & reg export "$key" "$OutFile" /y | Out-Null
  }
  Write-Log "Exported registry backup for $CAName -> $OutFile"
}

function Build-CA-RegPatch {
  param(
    [string]$CAName,
    [string[]]$AddCRL,
    [string[]]$AddAIA,
    [string[]]$AddAIAExt,
    [string]$OutFile
  )
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
    Write-Log "No new lines to add for $CAName; patch not needed."
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

  ($hdr + $body + "") | Out-File -FilePath $OutFile -Encoding ascii
  Write-Log "Staged patch for $CAName -> $OutFile"
  return $OutFile
}

function Phase4B-GuardedCRL_AIA_OCSP {
  Write-Log "Phase 4B - Guarded registry change staging for CRL/AIA/OCSP"
  Ensure-ConfigSkeleton
  if (-not (Test-Path $Global:GuardedConfigPath)) { Write-Log "Config file missing: $Global:GuardedConfigPath" 'ERROR'; return }
  $cfg = Get-Content $Global:GuardedConfigPath -Raw | ConvertFrom-Json

  $cas = Get-CARegistryKeys
  if (-not $cas) { Write-Log "No CAs found in registry on this host." 'WARN'; return }

  foreach ($entry in $cfg.CAs) {
    $target = $cas | Where-Object { $_.CAName -eq $entry.CAName }
    if (-not $target) { Write-Log "CA `"$($entry.CAName)`" not found on this host; skipping." 'WARN'; continue }

    # Backup current registry for this CA
    $backup = Join-Path "$OutDir\work" ("{0}-{1:yyyyMMddHHmmss}-backup.reg" -f $entry.CAName,(Get-Date))
    Export-CA-RegBackup -CAName $entry.CAName -OutFile $backup

    # Build patch
    $patch = Join-Path "$OutDir\work" ("{0}-{1:yyyyMMddHHmmss}-patch.reg" -f $entry.CAName,(Get-Date))
    $patchPath = Build-CA-RegPatch -CAName $entry.CAName `
      -AddCRL   $entry.Additions.CRLPublicationURLs `
      -AddAIA   $entry.Additions.CACertPublicationURLs `
      -AddAIAExt $entry.Additions.AuthorityInformationAccess `
      -OutFile  $patch

    if ($patchPath -and $Global:ApplyGuardedChanges) {
      # Apply patch
      Do-Or-Preview -Preview "reg import `"$patchPath`"" -Action { & reg import "$patchPath" | Out-Null }
      Write-Log "Applied patch -> $patchPath"
      Write-Log "Restarting CertSvc to pick up changes..."
      Do-Or-Preview -Preview "Restart-Service CertSvc" -Action { Restart-Service CertSvc -Force -ErrorAction Stop }
      Write-Log "CertSvc restarted."
    } elseif ($patchPath) {
      Write-Log "Patch staged (not applied). Review & apply later -> $patchPath"
    }
  }

  Write-Log "Phase 4B complete."
}

#====================================#
# PHASE 5: TRUST PROPAGATION (GPO)   #
#====================================#
function Phase5-TrustPropagation {
  Write-Log "Phase 5 - Trust propagation helper (GPO INF stub)"
  $infPath = Join-Path "$OutDir\work" 'trustedroots.inf'
  $blob = @"
[Version]
signature=`"$CHICAGO$`"
Revision=1

; Use your preferred tooling (LGPO/CI/Intune) to import CERs below
; Place CER files into this folder and import via your pipeline.
"@
  $blob | Out-File $infPath -Encoding ascii
  Write-Log "Generated GPO helper INF: $infPath"
}

#================================#
# PHASE 6: CLOUD INTEGRATIONS    #
#================================#
function Phase6-CloudIntegrations {
  Write-Log "Phase 6 - Cloud: Azure Key Vault / Keyfactor"

  # Azure Key Vault (import root/intermediates for trust/policy reference)
  if ($Global:VaultName) {
    $rootCer = Get-ChildItem "$OutDir\exports" -Filter *.cer | Select-Object -First 1
    if ($rootCer) {
      Do-Or-Preview -Preview "az keyvault certificate import --vault-name $($Global:VaultName) --name EnterpriseRoot --file $($rootCer.FullName)" -Action {
        & az keyvault certificate import --vault-name $Global:VaultName --name EnterpriseRoot --file $rootCer.FullName | Out-Null
      }
      Write-Log "AKV import attempted for root."
    } else {
      Write-Log "No root CER found to import to AKV." 'WARN'
    }
  } else {
    Write-Log "AKV vault name not set; skipping."
  }

  # Keyfactor CA registration
  if ($Global:KeyfactorBaseUrl -and $Global:KeyfactorApiKey) {
    $rootCer = Get-ChildItem "$OutDir\exports" -Filter *.cer | Select-Object -First 1
    if ($rootCer) {
      $payload = @{
        CommonName  = ($Global:AuthoritativeRootCN ?? 'AuthoritativeRoot')
        CAType      = 'Root'
        Certificate = (Get-Content $rootCer.FullName -Raw)
      } | ConvertTo-Json
      Do-Or-Preview -Preview "POST $($Global:KeyfactorBaseUrl)/KeyfactorAPI/CertificateAuthorities" -Action {
        Invoke-RestMethod -Method Post -Uri "$($Global:KeyfactorBaseUrl)/KeyfactorAPI/CertificateAuthorities" `
          -Headers @{ "x-keyfactor-requested-with"="APIClient"; "Authorization"="Bearer $($Global:KeyfactorApiKey)" } `
          -Body $payload -ContentType 'application/json' | Out-Null
      }
      Write-Log "Keyfactor CA registration attempted."
    } else {
      Write-Log "No root CER to register in Keyfactor." 'WARN'
    }
  } else {
    Write-Log "Keyfactor settings not provided; skipping."
  }
}

#================================#
# PHASE 7: LEAF RE-ISSUANCE      #
#================================#
function Phase7-LeafReissue {
  Write-Log "Phase 7 - Triggering leaf re-issuance paths"
  Do-Or-Preview -Preview 'gpupdate /force' -Action { & gpupdate /force | Out-Null }
  Do-Or-Preview -Preview 'certutil -pulse' -Action { & certutil -pulse | Out-Null }
  Write-Log "Triggered group policy refresh and auto-enrollment pulse."

  if ($Global:KeyfactorBaseUrl -and $Global:KeyfactorApiKey -and $Global:AuthoritativeRootCN) {
    $q = @{ Query = "Issuer NOT CONTAINS `"$($Global:AuthoritativeRootCN)`"" } | ConvertTo-Json
    Do-Or-Preview -Preview "POST search non-compliant certs in Keyfactor" -Action {
      Invoke-RestMethod -Method Post -Uri "$($Global:KeyfactorBaseUrl)/KeyfactorAPI/Certificates/Search" `
        -Headers @{ "x-keyfactor-requested-with"="APIClient"; "Authorization"="Bearer $($Global:KeyfactorApiKey)" } `
        -Body $q -ContentType "application/json" | Out-Null
    }
    Write-Log "Keyfactor search kicked (review portal/workflows to renew)."
  }
}

#==========================#
# PHASE 8: VERIFICATION    #
#==========================#
function Phase8-Verify {
  Write-Log "Phase 8 - Verifying leaf chains"
  if (-not $Global:AuthoritativeRootCN) { Phase2-SelectRoot }
  $outCsv = Join-Path "$OutDir\reports" 'Leaf-Verification.csv'

  $targets = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue
  $rows = foreach ($c in $targets) {
    $tmp = Join-Path "$OutDir\work" "$($c.Thumbprint).cer"
    Export-Certificate -Cert $c -FilePath $tmp | Out-Null
    $v = & certutil -verify $tmp 2>&1
    [pscustomobject]@{
      Subject   = $c.Subject
      Issuer    = $c.Issuer
      NotAfter  = $c.NotAfter
      ChainsToAuthoritativeRoot = ($v -match [regex]::Escape(($Global:AuthoritativeRootCN -replace '^Subject:\s*','')))
    }
  }
  $rows | Export-Csv $outCsv -NoTypeInformation
  Write-Log "Verification written -> $outCsv"
}

#=================================#
# PHASE 9: DECOMMISSION (UNPUBLISH)
#=================================#
function Phase9-DecommissionLegacy {
  Write-Log "Phase 9 - Decommission (directory unpublish only)"
  if (-not $Global:AuthoritativeRootCN) { Phase2-SelectRoot }
  $legacy = Get-ChildItem "$OutDir\exports" -Filter *.cer | Where-Object {
    (Get-Content $_.FullName -Raw) -notmatch [regex]::Escape(($Global:AuthoritativeRootCN -replace '^CN=','CN='))
  }

  foreach ($cer in $legacy) {
    Do-Or-Preview -Preview "certutil -enterprise -delstore NTAuth $($cer.FullName)" -Action { & certutil -enterprise -delstore NTAuth $cer.FullName | Out-Null }
    Do-Or-Preview -Preview "certutil -delstore Root $($cer.FullName)" -Action       { & certutil -delstore Root $cer.FullName | Out-Null }
    Write-Log "Unpublished legacy CA from AD stores: $($cer.Name)"
  }
  Write-Log "NOTE: Keep legacy CRL distribution points online for lifetime of issued certs."
}

#====================#
# MENU UI            #
#====================#
function Show-Menu {
  Clear-Host
  Write-Host "=== PKI Consolidation Menu ===" -ForegroundColor Cyan
  Write-Host "OutDir: $OutDir"
  Write-Host "Authoritative Root: $($Global:AuthoritativeRootCN ?? '(not set yet)')"
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
  Write-Host "Q) Quit"
  Write-Host ""
}

function Invoke-Menu {
  do {
    Show-Menu
    $choice = Read-Host "Select option"
    try {
      switch ($choice.ToUpper()) {
        '1'  { Phase1-Audit }
        '2'  { Phase2-SelectRoot }
        '3'  { Phase3-GenSubCSR }
        '4'  { Phase4-AcceptAndPublish }
        '4A' { Phase4A-PublishCRL_AIA_OCSP }
        '4B' { Phase4B-GuardedCRL_AIA_OCSP }
        '5'  { Phase5-TrustPropagation }
        '6'  { Phase6-CloudIntegrations }
        '7'  { Phase7-LeafReissue }
        '8'  { Phase8-Verify }
        '9'  { Phase9-DecommissionLegacy }
        'D'  { $Global:DoDryRun = -not $Global:DoDryRun; Write-Log "DryRun toggled to $($Global:DoDryRun)" }
        'G'  { $Global:GuardedMode = -not $Global:GuardedMode; Write-Log "GuardedMode toggled to $($Global:GuardedMode)" }
        'A'  { $Global:ApplyGuardedChanges = -not $Global:ApplyGuardedChanges; Write-Log "ApplyGuardedChanges toggled to $($Global:ApplyGuardedChanges)" }
        'Q'  { break }
        default { Write-Host "Unknown selection." -ForegroundColor Yellow }
      }
    } catch {
      Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    }
    if ($choice -ne 'Q') {
      Write-Host ""; Read-Host "Press Enter to continue"
    }
  } while ($true)
}

#====================#
# ENTRYPOINT         #
#====================#
Invoke-Menu

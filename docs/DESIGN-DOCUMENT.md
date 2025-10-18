# PKI-Consolidation Tool - Detailed Design Document

**Version:** 1.0  
**Date:** October 18, 2025  
**Status:** Draft  
**Classification:** Internal - Confidential

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Overview](#2-system-overview)
3. [Architecture Design](#3-architecture-design)
4. [Component Specifications](#4-component-specifications)
5. [Security Architecture](#5-security-architecture)
6. [Data Flow & Workflows](#6-data-flow--workflows)
7. [Integration Points](#7-integration-points)
8. [Error Handling & Recovery](#8-error-handling--recovery)
9. [Performance Considerations](#9-performance-considerations)
10. [Compliance & Audit](#10-compliance--audit)
11. [Deployment Architecture](#11-deployment-architecture)
12. [Future Enhancements](#12-future-enhancements)

---

## 1. Executive Summary

### 1.1 Purpose

The PKI-Consolidation Tool is a PowerShell-based automation framework designed to facilitate the consolidation of multiple Active Directory Certificate Services (AD CS) environments during organizational mergers, acquisitions, or infrastructure modernization initiatives.

### 1.2 Business Drivers

- **M&A Integration**: Rapidly consolidate disparate PKI infrastructures from merged entities
- **Risk Reduction**: Minimize manual errors in critical certificate authority operations
- **Audit Trail**: Maintain comprehensive change tracking for compliance requirements
- **Operational Safety**: Implement "guarded mode" to stage and review changes before application

### 1.3 Key Capabilities

| Capability | Description | Business Value |
|------------|-------------|----------------|
| CA Discovery | Automated scanning of AD CS environment | Reduces manual inventory effort by 90% |
| Guarded Mode | Stage-review-apply workflow for registry changes | Eliminates unreviewed production changes |
| Multi-Cloud Integration | Azure Key Vault & Keyfactor support | Enables hybrid PKI architectures |
| Dry-Run Mode | Preview all operations without execution | Zero-risk validation of automation logic |
| Comprehensive Logging | Timestamped audit trail of all operations | Satisfies SOC2/ISO27001 audit requirements |

### 1.4 Design Principles

1. **Safety First**: All destructive operations require explicit confirmation
2. **Transparency**: Every action is logged with timestamp and context
3. **Idempotency**: Operations can be safely repeated without side effects
4. **Modularity**: Each phase operates independently with clear interfaces
5. **Extensibility**: JSON-driven configuration for adaptability

---

## 2. System Overview

### 2.1 System Context Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Enterprise Environment                        │
│                                                                   │
│  ┌──────────────┐         ┌──────────────┐      ┌─────────────┐│
│  │ Domain       │◄────────┤ PKI-         │─────►│ Certificate ││
│  │ Controllers  │         │ Consolidation│      │ Authorities ││
│  │ (AD)         │         │ Tool         │      │ (AD CS)     ││
│  └──────────────┘         └──────┬───────┘      └─────────────┘│
│                                   │                              │
│                                   ├──────────────────────────┐   │
│                                   │                          │   │
│                          ┌────────▼────────┐      ┌──────────▼┐ │
│                          │ Azure Key       │      │ Keyfactor │ │
│                          │ Vault           │      │ Platform  │ │
│                          └─────────────────┘      └───────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|----------|
| **Scripting Engine** | PowerShell | 5.1+ | Primary automation platform |
| **Directory Services** | Active Directory | Server 2016+ | PKI object storage |
| **PKI Infrastructure** | AD CS | Server 2016+ | Certificate issuance |
| **Configuration Format** | JSON | RFC 8259 | Declarative configuration |
| **Cloud Integration** | Azure CLI, REST APIs | Current | Multi-cloud support |
| **Logging** | Text-based logs | Custom | Audit trail |

### 2.3 System Requirements

#### 2.3.1 Hardware Requirements

- **Minimum**: 2 CPU cores, 4 GB RAM, 10 GB disk space
- **Recommended**: 4 CPU cores, 8 GB RAM, 50 GB disk space (for large PKI environments)

#### 2.3.2 Software Requirements

- Windows Server 2016 or later / Windows 10/11 Enterprise
- PowerShell 5.1 or later (PowerShell 7+ recommended for parallel processing)
- .NET Framework 4.7.2 or later
- Active Directory RSAT tools
- AD CS management tools (if managing local CAs)

#### 2.3.3 Permissions Requirements

| Permission Level | Operations Enabled | Justification |
|------------------|-------------------|---------------|
| **Enterprise Admin** | Phase 1, 2, 4, 5, 9 | AD schema modifications, CA publication |
| **Local Administrator** | Phase 3, 4A, 4B | Certificate enrollment, registry modifications |
| **CA Administrator** | All phases | Full CA configuration control |
| **Certificate Manager** | Phase 7, 8 | Certificate issuance and validation |

---

## 3. Architecture Design

### 3.1 Architectural Style

The PKI-Consolidation Tool follows a **modular procedural architecture** with the following characteristics:

- **Phase-based execution model**: Each consolidation phase is isolated
- **Functional decomposition**: Clear separation between utility, phase, and UI layers
- **Data-driven configuration**: Behavior controlled via JSON configuration files
- **State management**: File system-based state persistence

### 3.2 Logical Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                        Presentation Layer                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Interactive Menu (Show-Menu, Invoke-Menu)               │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
                              │
┌────────────────────────────────────────────────────────────────┐
│                      Business Logic Layer                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Phase Orchestration                                      │  │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐        │  │
│  │  │Phase1-9│  │Phase2  │  │Phase3  │  │Phase4  │  ...   │  │
│  │  │Audit   │  │Select  │  │GenCSR  │  │Publish │        │  │
│  │  └────────┘  └────────┘  └────────┘  └────────┘        │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
                              │
┌────────────────────────────────────────────────────────────────┐
│                     Utility/Service Layer                       │
│  ┌───────────────┐ ┌─────────────┐ ┌────────────────────────┐ │
│  │ Logging       │ │ Dry-Run     │ │ Registry Management    │ │
│  │ (Write-Log)   │ │ (Do-Or-     │ │ (Get-CARegistryKeys,   │ │
│  │               │ │  Preview)   │ │  Export-CA-RegBackup)  │ │
│  └───────────────┘ └─────────────┘ └────────────────────────┘ │
│  ┌───────────────┐ ┌─────────────┐ ┌────────────────────────┐ │
│  │ AD Integration│ │ Certificate │ │ Config Management      │ │
│  │ (Get-ConfigNC,│ │ Operations  │ │ (Ensure-               │ │
│  │  Export-ADCA) │ │ (Safe-      │ │  ConfigSkeleton)       │ │
│  │               │ │  Certutil)  │ │                        │ │
│  └───────────────┘ └─────────────┘ └────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
                              │
┌────────────────────────────────────────────────────────────────┐
│                      Integration Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │ Active       │  │ Certificate  │  │ Cloud Services     │   │
│  │ Directory    │  │ Services     │  │ (Azure/Keyfactor)  │   │
│  │ (LDAP/AD     │  │ (certutil,   │  │ (REST APIs)        │   │
│  │  PowerShell) │  │  certreq)    │  │                    │   │
│  └──────────────┘  └──────────────┘  └────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
```

### 3.3 Component Interaction Model

#### 3.3.1 Phase Execution Flow

```
User Selection
     │
     ▼
┌─────────────────┐
│ Input Validation│
└────────┬────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────┐
│ Dry-Run Check   │─────►│ Log Preview  │
└────────┬────────┘      └──────────────┘
         │ (Execute)
         ▼
┌─────────────────┐
│ Phase Logic     │
│ Execution       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Error Handler   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Result Logging  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ State           │
│ Persistence     │
└─────────────────┘
```

### 3.4 Data Architecture

#### 3.4.1 File System Structure

```
C:\PKI\Consolidation\
│
├── config\
│   └── crl-aia-ocsp.json          # Guarded mode configuration
│
├── exports\                        # Exported certificates
│   ├── CA1_cacert.cer
│   ├── CA2_cacert.cer
│   └── ...
│
├── reports\                        # Generated reports
│   ├── CA-Inventory.csv
│   ├── AuthoritativeRoot.txt
│   └── Leaf-Verification.csv
│
├── work\                           # Working directory
│   ├── SubCA1.subca.inf
│   ├── SubCA1.subca.req
│   ├── CA1-20251018123045-backup.reg
│   ├── CA1-20251018123045-patch.reg
│   └── issued\                     # Place issued certificates here
│       └── SubCA1.cer
│
└── PKI-Consolidation.log          # Audit log
```

#### 3.4.2 Configuration Schema

**File**: `config/crl-aia-ocsp.json`

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "CAs": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "CAName": {
            "type": "string",
            "description": "Display name of CA as it appears in registry"
          },
          "Additions": {
            "type": "object",
            "properties": {
              "CRLPublicationURLs": {
                "type": "array",
                "items": { "type": "string" },
                "description": "CRL distribution points with numeric flags"
              },
              "CACertPublicationURLs": {
                "type": "array",
                "items": { "type": "string" },
                "description": "AIA certificate publication URLs"
              },
              "AuthorityInformationAccess": {
                "type": "array",
                "items": { "type": "string" },
                "description": "AIA extension values including OCSP"
              }
            }
          }
        },
        "required": ["CAName", "Additions"]
      }
    }
  },
  "required": ["CAs"]
}
```

#### 3.4.3 State Management

| State Element | Storage Location | Format | Persistence |
|---------------|------------------|--------|-------------|
| CA Inventory | `reports/CA-Inventory.csv` | CSV | Persistent |
| Authoritative Root | `reports/AuthoritativeRoot.txt` | Text | Persistent |
| Registry Backups | `work/*.reg` | REG file | Persistent |
| Log Entries | `PKI-Consolidation.log` | Text | Append-only |
| Runtime Config | Global variables | In-memory | Session |

---

## 4. Component Specifications

### 4.1 Core Components

#### 4.1.1 Bootstrap & Configuration

**Component**: Bootstrap  
**Location**: Lines 55-101  
**Responsibility**: Initialize environment, load modules, create directory structure

**Key Functions**:
- `$ErrorActionPreference = 'Stop'`: Global error handling policy
- Directory creation: Ensures output directory structure exists
- Module loading: Attempts to import AD, GroupPolicy, PSPKI modules

**Dependencies**:
- Windows PowerShell 5.1+
- File system write permissions

**Configuration Parameters**:
```powershell
$Global:OutDir                 = 'C:\PKI\Consolidation'
$Global:AuthoritativeRootCN    = $null
$Global:VaultName              = ''
$Global:KeyfactorBaseUrl       = ''
$Global:KeyfactorApiKey        = ''
$Global:DoDryRun               = $false
$Global:GuardedMode            = $true
$Global:ApplyGuardedChanges    = $false
$Global:EnableVerboseLog       = $true
$Global:GuardedConfigPath      = Join-Path $OutDir 'config\crl-aia-ocsp.json'
$Global:LogPath                = Join-Path $OutDir 'PKI-Consolidation.log'
```

#### 4.1.2 Logging Subsystem

**Component**: Write-Log  
**Location**: Lines 82-87  
**Responsibility**: Centralized logging with severity levels

**Function Signature**:
```powershell
function Write-Log {
  param([string]$Msg, [string]$Level='INFO')
}
```

**Severity Levels**:
- `INFO`: Normal operational messages
- `WARN`: Non-critical issues that should be reviewed
- `ERROR`: Critical failures requiring intervention

**Log Format**:
```
2025-10-18 14:32:45Z [INFO] Phase 1 - Discovering Enterprise CAs
2025-10-18 14:32:46Z [WARN] ActiveDirectory module unavailable
2025-10-18 14:32:50Z [ERROR] Failed to export cACertificate for CA2
```

#### 4.1.3 Dry-Run Wrapper

**Component**: Do-Or-Preview  
**Location**: Lines 89-96  
**Responsibility**: Conditional execution based on dry-run flag

**Function Signature**:
```powershell
function Do-Or-Preview {
  param(
    [Parameter(Mandatory)][scriptblock]$Action,
    [string]$Preview = ''
  )
}
```

**Behavior**:
- If `$Global:DoDryRun = $true`: Logs preview message only
- If `$Global:DoDryRun = $false`: Executes the scriptblock

### 4.2 Phase Components

#### 4.2.1 Phase 1: CA Discovery & Audit

**Component**: Phase1-Audit  
**Location**: Lines 202-233  
**Inputs**: Active Directory PKI container  
**Outputs**: `reports/CA-Inventory.csv`

**Algorithm**:
1. Query AD for all `pKIEnrollmentService` objects
2. For each CA:
   - Export CA certificate from `cACertificate` attribute
   - Parse certificate details using `certutil -dump`
   - Extract: Subject, Issuer, Signature Algorithm, Expiration, Templates
3. Export consolidated inventory to CSV

**Data Model** (CA-Inventory.csv):
```
CA_CN,Hostname,DN,Subject,Issuer,SigAlgorithm,NotAfterRaw,Templates,CertPath
```

#### 4.2.2 Phase 2: Root Selection

**Component**: Phase2-SelectRoot  
**Location**: Lines 238-256  
**Inputs**: `reports/CA-Inventory.csv`  
**Outputs**: `reports/AuthoritativeRoot.txt`, `$Global:AuthoritativeRootCN`

**Selection Algorithm**:
1. If `$Global:AuthoritativeRootCN` is preset, use it
2. Else, filter for self-signed CAs (Subject == Issuer)
3. Prefer SHA-2 algorithm (sha256/384/512)
4. Select first match
5. Persist selection to file and global variable

**Decision Logic**:
```
Preset Root? ──Yes──► Use preset value
     │
    No
     │
     ▼
Self-signed CAs ──► Filter SHA-2 ──► Select first ──► Persist
                         │
                   No SHA-2?
                         │
                         ▼
                   Select any root
```

#### 4.2.3 Phase 3: Sub-CA CSR Generation

**Component**: Phase3-GenSubCSR  
**Location**: Lines 261-300  
**Inputs**: `reports/CA-Inventory.csv`  
**Outputs**: `work/*.subca.inf`, `work/*.subca.req`

**Certificate Request Template**:
```ini
[Version]
Signature="$Windows NT$"

[NewRequest]
Subject = "<extracted from inventory>"
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
```

**Key Parameters**:
- **Key Length**: 4096 bits (industry best practice for CA keys)
- **Hash Algorithm**: SHA-256 (NIST recommended, FIPS 140-2 compliant)
- **Exportable**: TRUE (required for backup/recovery scenarios)
- **Path Length**: 0 (subordinate CA cannot issue further sub-CAs)

#### 4.2.4 Phase 4: Certificate Acceptance & Publishing

**Component**: Phase4-AcceptAndPublish  
**Location**: Lines 305-338  
**Inputs**: `work/issued/*.cer`  
**Operations**: Accept certificates, publish to AD

**Publishing Sequence**:
```
1. Accept Sub-CA Certificates
   ├─► certreq -accept <cert.cer>
   └─► Installs to LocalMachine\CA store

2. Publish Authoritative Root
   └─► certutil -dspublish -f <root.cer> RootCA
       └─► CN=Certification Authorities,CN=Public Key Services,CN=Services,CN=Configuration

3. Publish Sub-CAs
   └─► certutil -dspublish -f <subca.cer> SubCA
       └─► CN=AIA,CN=Public Key Services,CN=Services,CN=Configuration

4. Publish to NTAuth Store
   └─► certutil -dspublish -f <issuer.cer> NTAuthCA
       └─► Required for smart card logon
```

#### 4.2.5 Phase 4A: CRL/AIA Publication & OCSP Health

**Component**: Phase4A-PublishCRL_AIA_OCSP  
**Location**: Lines 343-406  
**Inputs**: Local CA registry configuration  
**Operations**: Generate CRLs, publish distribution points, validate OCSP

**Workflow**:
```
For each local CA:
  1. Generate fresh CRL
     └─► certutil -crl
  
  2. Publish CRL to AD
     └─► certutil -dspublish -f <crl.crl>
  
  3. Copy CRL to file-based distribution points
     └─► Parse CRLPublicationURLs from registry
     └─► Copy to local file:// targets
  
  4. Publish CA certificates to AIA
     └─► certutil -dspublish -f <ca.cer> SubCA
     └─► Copy to CACertPublicationURLs targets
  
  5. OCSP Health Check
     └─► Detect OCSPSvc service
     └─► Extract OCSP URLs from AuthorityInformationAccess
     └─► Probe endpoints: certutil -verify -urlfetch
```

#### 4.2.6 Phase 4B: Guarded Registry Changes

**Component**: Phase4B-GuardedCRL_AIA_OCSP  
**Location**: Lines 477-515  
**Inputs**: `config/crl-aia-ocsp.json`  
**Outputs**: `work/*-backup.reg`, `work/*-patch.reg`

**Guarded Mode Philosophy**:
1. **Detect**: Read current registry values
2. **Validate**: Compare against desired state from JSON
3. **Stage**: Generate `.reg` patch file with additions only
4. **Review**: Manual review in version control
5. **Apply**: Import `.reg` file if `ApplyGuardedChanges = $true`

**Registry Value Format** (REG_MULTI_SZ):
```
"CRLPublicationURLs"=hex(7):36,00,35,00,3a,00,66,00,69,00,6c,00,65,00,...
```
- Format: `hex(7)` = REG_MULTI_SZ
- Encoding: Unicode (UTF-16LE)
- Delimiter: `\0` (null character between strings)
- Terminator: `\0\0` (double null at end)

**Safety Mechanisms**:
- Pre-change backup via `reg export`
- Timestamped filenames prevent overwrites
- Diff-based additions (no deletions/modifications)
- Service restart only if patch applied successfully

#### 4.2.7 Phase 5: Trust Propagation

**Component**: Phase5-TrustPropagation  
**Location**: Lines 520-533  
**Outputs**: `work/trustedroots.inf`

**Purpose**: Generate helper files for Group Policy-based certificate distribution

**Integration Points**:
- LGPO.exe (Microsoft Local Group Policy Object tool)
- Configuration Manager / Intune certificate profiles
- Custom GPO deployment pipelines

#### 4.2.8 Phase 6: Cloud Integrations

**Component**: Phase6-CloudIntegrations  
**Location**: Lines 538-577

**6a. Azure Key Vault Integration**

**Purpose**: Import enterprise root/intermediate certificates to Azure for:
- Azure App Service certificate validation
- Azure API Management mTLS
- Cross-cloud trust establishment

**Operation**:
```powershell
az keyvault certificate import \
  --vault-name <VaultName> \
  --name EnterpriseRoot \
  --file <root.cer>
```

**6b. Keyfactor Integration**

**Purpose**: Register CAs with Keyfactor Command for:
- Centralized certificate lifecycle management
- Automated renewal workflows
- Compliance reporting

**API Endpoint**:
```
POST https://<KeyfactorBaseUrl>/KeyfactorAPI/CertificateAuthorities
Headers:
  x-keyfactor-requested-with: APIClient
  Authorization: Bearer <ApiKey>
Body:
{
  "CommonName": "Authoritative Root",
  "CAType": "Root",
  "Certificate": "<PEM encoded>"
}
```

#### 4.2.9 Phase 7: Leaf Re-issuance

**Component**: Phase7-LeafReissue  
**Location**: Lines 582-597

**Trigger Mechanisms**:
1. **Group Policy Refresh**: `gpupdate /force`
2. **Auto-Enrollment Pulse**: `certutil -pulse`
3. **Keyfactor Search**: Query for non-compliant certificates

**Use Case**: After sub-CA consolidation, force re-issuance of end-entity certificates to establish chain to new authoritative root

#### 4.2.10 Phase 8: Verification

**Component**: Phase8-Verify  
**Location**: Lines 602-621  
**Outputs**: `reports/Leaf-Verification.csv`

**Validation Logic**:
```powershell
foreach (certificate in LocalMachine\My) {
  certutil -verify <cert> | 
    Match against $AuthoritativeRootCN
}
```

**Report Fields**:
- Subject
- Issuer
- NotAfter
- ChainsToAuthoritativeRoot (Boolean)

#### 4.2.11 Phase 9: Decommission

**Component**: Phase9-DecommissionLegacy  
**Location**: Lines 626-639

**Operations**:
1. Identify legacy CAs (not matching authoritative root)
2. Remove from NTAuth store
3. Remove from Trusted Root store
4. Log unpublish actions

**Safety Note**: Does NOT shut down CA services or delete CRL distribution points (required for issued certificate validation until expiration)

### 4.3 Utility Components

#### 4.3.1 Registry Key Enumeration

**Component**: Get-CARegistryKeys  
**Location**: Lines 125-150

**Returns**: PSCustomObject array with:
- `CAName`: Display name
- `Path`: Registry path
- `CRLUrls`: Array of CRL publication URLs
- `AIAUrls`: Array of AIA certificate URLs
- `AIAExt`: AuthorityInformationAccess extension values
- `OCSPUrls`: Extracted OCSP responder URLs

**Registry Path**: `HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\<CAName>`

#### 4.3.2 Certificate Export

**Component**: Export-ADCA-Cert  
**Location**: Lines 109-114

**Purpose**: Extract binary certificate from AD object's `cACertificate` attribute

**Challenges**:
- `cACertificate` is multi-valued (supports renewal)
- Select-Object -First 1 gets most recent
- Binary data must be written with `[IO.File]::WriteAllBytes()`

#### 4.3.3 Safe Certutil Wrapper

**Component**: Safe-Certutil  
**Location**: Lines 116-123

**Purpose**: Wrap certutil calls with dry-run support and output logging

**Certutil Commands Used**:
- `-dump`: Parse certificate details
- `-crl`: Generate CRL
- `-dspublish`: Publish to AD containers
- `-verify`: Validate certificate chain
- `-urlfetch`: Test CRL/OCSP endpoints
- `-pulse`: Trigger auto-enrollment

---

## 5. Security Architecture

### 5.1 Threat Model

#### 5.1.1 Assets

| Asset | Classification | Threat Level |
|-------|----------------|--------------|
| CA Private Keys | Critical | High |
| CA Registry Configuration | High | High |
| API Keys (Keyfactor, Azure) | High | High |
| Audit Logs | Medium | Medium |
| CA Certificates (Public) | Low | Low |

#### 5.1.2 Threat Analysis

**T1: Credential Exposure**
- **Threat**: API keys stored in plaintext global variables
- **Attack Vector**: Memory dump, script echo, log file exposure
- **Impact**: Unauthorized access to Keyfactor/Azure environments
- **Likelihood**: High (credentials in plaintext)
- **Risk Rating**: High

**T2: Unauthorized Registry Modification**
- **Threat**: Malicious patch file imported without review
- **Attack Vector**: Supply chain attack on JSON config, compromised workstation
- **Impact**: CA misconfiguration, certificate validation failure
- **Likelihood**: Medium (guarded mode provides review step)
- **Risk Rating**: High

**T3: Privilege Escalation**
- **Threat**: Script executed by non-privileged user
- **Attack Vector**: Stolen credentials, social engineering
- **Impact**: Unauthorized CA operations, certificate issuance
- **Likelihood**: Low (requires admin permissions)
- **Risk Rating**: Medium

**T4: Audit Trail Tampering**
- **Threat**: Log file modified to hide malicious activity
- **Attack Vector**: File system access, log injection
- **Impact**: Undetected security incidents, compliance failure
- **Likelihood**: Medium (logs are plaintext files)
- **Risk Rating**: Medium

**T5: Denial of Service**
- **Threat**: CA service restart during high-utilization period
- **Attack Vector**: Poorly timed patch application
- **Impact**: Certificate issuance unavailable, business disruption
- **Likelihood**: Medium (no health check before restart)
- **Risk Rating**: Medium

### 5.2 Security Controls

#### 5.2.1 Implemented Controls

| Control ID | Control Type | Description | Effectiveness |
|------------|--------------|-------------|---------------|
| SC-01 | Preventive | Dry-run mode prevents accidental execution | High |
| SC-02 | Detective | Comprehensive audit logging | Medium |
| SC-03 | Preventive | Guarded mode stage-review-apply | High |
| SC-04 | Corrective | Registry backup before changes | High |
| SC-05 | Preventive | `$ErrorActionPreference = 'Stop'` | Medium |

#### 5.2.2 Recommended Additional Controls

**AC-01: Credential Management**
```powershell
# Current (INSECURE):
$Global:KeyfactorApiKey = ''

# Recommended (SECURE):
$Global:KeyfactorApiKey = Get-SecretFromVault -VaultName 'PKI-Vault' -SecretName 'KeyfactorAPIKey'

# Implementation:
function Get-SecretFromVault {
  param([string]$VaultName, [string]$SecretName)
  
  # Option 1: Windows Credential Manager
  $cred = Get-StoredCredential -Target "$VaultName/$SecretName"
  return $cred.Password
  
  # Option 2: Azure Key Vault
  $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -AsPlainText
  return $secret
  
  # Option 3: CyberArk, HashiCorp Vault, etc.
}
```

**AC-02: Privilege Validation**
```powershell
function Test-RequiredPermissions {
  # Check local administrator
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "This script requires local administrator privileges." }
  
  # Check Enterprise Admin membership
  $user = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object System.Security.Principal.WindowsPrincipal($user)
  $enterpriseAdmins = "CN=Enterprise Admins,CN=Users,$(Get-ConfigNC)"
  
  try {
    $group = Get-ADGroup -Identity $enterpriseAdmins
    $isMember = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.SID -eq $user.User }
    if (-not $isMember) { Write-Log "WARNING: Not an Enterprise Admin. Some operations may fail." 'WARN' }
  } catch {
    Write-Log "Could not verify Enterprise Admin membership: $($_.Exception.Message)" 'WARN'
  }
}

# Call in Bootstrap section
Test-RequiredPermissions
```

**AC-03: File Permissions Hardening**
```powershell
function Set-SecureDirectoryACLs {
  param([string]$Path)
  
  # Remove inherited permissions
  $acl = Get-Acl $Path
  $acl.SetAccessRuleProtection($true, $false)
  
  # Grant only SYSTEM and Administrators
  $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
  )
  $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
  )
  
  $acl.SetAccessRule($systemRule)
  $acl.SetAccessRule($adminRule)
  Set-Acl -Path $Path -AclObject $acl
  
  Write-Log "Secured directory: $Path"
}

# Apply to sensitive directories
Set-SecureDirectoryACLs -Path "$OutDir\work"
Set-SecureDirectoryACLs -Path "$OutDir\config"
```

**AC-04: Log Integrity Protection**
```powershell
function Write-SecureLog {
  param([string]$Msg, [string]$Level='INFO')
  
  $line = '{0:u} [{1}] {2}' -f (Get-Date), $Level.ToUpper(), $Msg
  
  # Calculate HMAC for integrity
  $key = Get-SecretFromVault -VaultName 'PKI-Vault' -SecretName 'LogHMACKey'
  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($key)
  $hash = [BitConverter]::ToString($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($line)))
  
  $securedLine = "$line | HMAC:$hash"
  
  if ($Global:EnableVerboseLog) { Write-Host $line }
  Add-Content -Path $Global:LogPath -Value $securedLine
}
```

**AC-05: Input Validation**
```powershell
function Validate-JSONConfig {
  param([string]$ConfigPath)
  
  if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
  }
  
  try {
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
  } catch {
    throw "Invalid JSON syntax in $ConfigPath : $($_.Exception.Message)"
  }
  
  # Schema validation
  if (-not $cfg.CAs) { throw "Configuration missing 'CAs' array" }
  
  foreach ($ca in $cfg.CAs) {
    if (-not $ca.CAName) { throw "CA entry missing 'CAName' property" }
    if (-not $ca.Additions) { throw "CA '$($ca.CAName)' missing 'Additions' property" }
    
    # Validate URL formats
    foreach ($url in $ca.Additions.CRLPublicationURLs) {
      if ($url -notmatch '^\d+:') { throw "Invalid CRL URL format: $url" }
    }
  }
  
  Write-Log "Configuration validated successfully: $ConfigPath"
  return $cfg
}
```

### 5.3 Compliance Mapping

| Compliance Framework | Relevant Controls | Implementation Status |
|---------------------|-------------------|----------------------|
| **SOC 2 Type II** | CC6.1 (Logical access controls) | Partial (needs AC-02) |
| | CC7.2 (System monitoring) | Implemented (logging) |
| **ISO 27001:2013** | A.9.2.3 (Privileged access management) | Partial (needs AC-01) |
| | A.12.4.1 (Event logging) | Implemented |
| **NIST 800-53** | AC-2 (Account Management) | Partial |
| | AU-9 (Audit log protection) | Missing (needs AC-04) |
| **PCI DSS 3.2.1** | Req 8.7 (Restrict admin access) | Partial |
| | Req 10.5 (Protect audit trails) | Missing |

---

## 6. Data Flow & Workflows

### 6.1 Consolidation Workflow

```
┌────────────────────────────────────────────────────────────────────┐
│                   Pre-Consolidation Phase                          │
└────────────────────┬───────────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 1: Audit CAs     │──────► CA-Inventory.csv
        └────────────┬───────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 2: Select Root   │──────► AuthoritativeRoot.txt
        └────────────┬───────────┘
                     │
┌────────────────────────────────────────────────────────────────────┐
│                    Certificate Issuance Phase                      │
└────────────────────┬───────────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 3: Gen Sub-CSRs  │──────► *.subca.req
        └────────────┬───────────┘
                     │
                     ▼
        ┌────────────────────────────────────┐
        │ MANUAL: Submit CSRs to Root CA     │
        │ Place issued certs in work/issued/ │
        └────────────┬───────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 4: Accept & Pub  │──────► AD Published
        └────────────┬───────────┘
                     │
┌────────────────────────────────────────────────────────────────────┐
│                  Distribution Point Configuration                  │
└────────────────────┬───────────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 4A: Publish      │──────► CRLs, OCSP Health
        │          CRL/AIA       │
        └────────────┬───────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 4B: Guarded Reg  │──────► *.reg patches
        │         (Stage & Apply)│
        └────────────┬───────────┘
                     │
┌────────────────────────────────────────────────────────────────────┐
│                   Trust Distribution Phase                         │
└────────────────────┬───────────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 5: Trust Prop    │──────► GPO helpers
        └────────────┬───────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 6: Cloud Integ   │──────► AKV, Keyfactor
        └────────────┬───────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 7: Leaf Reissue  │──────► Trigger renewal
        └────────────┬───────────┘
                     │
┌────────────────────────────────────────────────────────────────────┐
│                   Post-Consolidation Phase                         │
└────────────────────┬───────────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 8: Verification  │──────► Leaf-Verification.csv
        └────────────┬───────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │ Phase 9: Decommission  │──────► Legacy CAs unpublished
        └────────────────────────┘
```

### 6.2 Guarded Mode Detailed Flow

```
                  ┌─────────────────────┐
                  │ Edit JSON Config    │
                  │ crl-aia-ocsp.json   │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │ Phase 4B: Guarded   │
                  │ Registry Changes    │
                  └──────────┬──────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
     ┌─────────────────────┐   ┌─────────────────────┐
     │ Read Current Values │   │ Parse JSON Config   │
     │ from Registry       │   │ (Desired State)     │
     └──────────┬──────────┘   └──────────┬──────────┘
                │                         │
                └────────────┬────────────┘
                             ▼
                  ┌─────────────────────┐
                  │ Export Backup .reg  │
                  │ (CA1-timestamp.reg) │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │ Compute Diff        │
                  │ (Additions only)    │
                  └──────────┬──────────┘
                             │
                      No additions?
                             │
                 Yes ◄───────┴────────► No
                  │                      │
                  ▼                      ▼
     ┌─────────────────────┐   ┌─────────────────────┐
     │ Log: No changes     │   │ Build Patch .reg    │
     │ needed              │   │ (CA1-timestamp.reg) │
     └─────────────────────┘   └──────────┬──────────┘
                                          │
                            ┌─────────────┴─────────────┐
                            │ ApplyGuardedChanges?      │
                            └─────────────┬─────────────┘
                                     │
                        False ◄──────┴────────► True
                          │                      │
                          ▼                      ▼
             ┌─────────────────────┐   ┌─────────────────────┐
             │ Log: Staged only    │   │ reg import patch    │
             │ Review manually     │   └──────────┬──────────┘
             └─────────────────────┘              │
                                                  ▼
                                       ┌─────────────────────┐
                                       │ Restart CertSvc     │
                                       └──────────┬──────────┘
                                                  │
                                                  ▼
                                       ┌─────────────────────┐
                                       │ Verify Service OK   │
                                       └─────────────────────┘
```

### 6.3 Data Flow Diagram (DFD) - Level 1

```
                         ┌──────────────┐
                         │   Operator   │
                         └──────┬───────┘
                                │
                                │ Menu Selection
                                │
                                ▼
                    ┌───────────────────────┐
                    │                       │
    ┌──────────────►│  PKI-Consolidation   │◄──────────────┐
    │               │      Tool            │               │
    │               │                       │               │
    │               └───────────┬───────────┘               │
    │                           │                           │
    │                           │                           │
    │ Certificates              │ LDAP Queries              │ Registry
    │ Logs                      │ Certificate Ops           │ .reg files
    │                           │                           │
    ▼                           ▼                           ▼
┌──────────┐            ┌──────────────┐          ┌────────────────┐
│   File   │            │   Active     │          │  Local CA      │
│  System  │            │   Directory  │          │  Registry      │
│          │            │              │          │                │
└──────────┘            └──────────────┘          └────────────────┘
                                │
                                │ Certificate Validation
                                │
                                ▼
                        ┌──────────────┐
                        │ Certificate  │
                        │ Services     │
                        │ (certutil,   │
                        │  certreq)    │
                        └──────────────┘
```

---

## 7. Integration Points

### 7.1 Active Directory Integration

**Protocol**: LDAP/LDAPS  
**Authentication**: Kerberos (Windows Integrated)  
**Objects Accessed**:
- `CN=Public Key Services,CN=Services,CN=Configuration,DC=...`
- `CN=Certification Authorities` (Root CA publication)
- `CN=AIA` (Authority Information Access)
- `CN=Enrollment Services` (CA objects)
- `CN=NTAuthCertificates` (Smart card trust)

**Operations**:
- `Get-ADObject`: Query PKI objects
- `Get-ADRootDSE`: Discover configuration naming context
- `certutil -dspublish`: Publish certificates to AD containers

**Failure Modes**:
- LDAP timeout: Retry with exponential backoff
- Insufficient permissions: Require Enterprise Admin
- Schema mismatch: Validate forest functional level >= 2008

### 7.2 Certificate Services Integration

**Interface**: Command-line utilities (`certutil.exe`, `certreq.exe`)  
**Communication**: Local RPC, file system

**certutil Operations**:
| Command | Purpose | Error Handling |
|---------|---------|----------------|
| `-dump` | Parse certificate details | Check exit code; fallback to `openssl` |
| `-crl` | Generate CRL | Verify CRL file created |
| `-dspublish` | Publish to AD | Validate LDAP connection |
| `-verify` | Validate chain | Parse output for "Verified" |
| `-urlfetch` | Test CDP/AIA/OCSP | Network timeout detection |
| `-pulse` | Trigger auto-enrollment | No-op if service unavailable |

**certreq Operations**:
| Command | Purpose | Error Handling |
|---------|---------|----------------|
| `-new` | Generate CSR from INF | Validate INF syntax |
| `-accept` | Install issued certificate | Check private key binding |

### 7.3 Azure Key Vault Integration

**API**: Azure CLI (`az keyvault`)  
**Authentication**: Azure AD (Managed Identity, Service Principal, User)  
**Prerequisites**:
- Azure CLI installed
- `az login` completed
- Vault access policy grants: Certificate Import

**Operations**:
```bash
az keyvault certificate import \
  --vault-name <name> \
  --name <cert-name> \
  --file <path> \
  [--policy <policy-json>]
```

**Error Handling**:
- 403 Forbidden: Check access policies
- 404 Not Found: Validate vault name and subscription
- Network errors: Retry with exponential backoff

### 7.4 Keyfactor Integration

**API**: REST API (JSON)  
**Authentication**: Bearer token in `Authorization` header  
**Base URL**: `https://<keyfactor-host>/KeyfactorAPI`

**Endpoints Used**:
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/CertificateAuthorities` | POST | Register CA |
| `/Certificates/Search` | POST | Query certificates |

**Request Format** (CA Registration):
```json
POST /KeyfactorAPI/CertificateAuthorities
Headers:
  x-keyfactor-requested-with: APIClient
  Authorization: Bearer <token>
  Content-Type: application/json

Body:
{
  "CommonName": "Authoritative Root CA",
  "CAType": "Root",
  "Certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
}
```

**Response Codes**:
- 200 OK: Success
- 400 Bad Request: Invalid certificate format
- 401 Unauthorized: Invalid API key
- 409 Conflict: CA already registered

### 7.5 Group Policy Integration

**Mechanism**: INF file generation for manual GPO import  
**Tools**: LGPO.exe, Group Policy Management Console  
**Distribution Methods**:
1. **LGPO**: `LGPO.exe /g <GPO-backup-folder>`
2. **Intune**: Certificate profile deployment
3. **SCCM**: Configuration item with PowerShell script

**Certificate Distribution**:
```
GPO Path: Computer Configuration\Windows Settings\Security Settings\
          Public Key Policies\Trusted Root Certification Authorities
```

---

## 8. Error Handling & Recovery

### 8.1 Error Categories

| Category | Examples | Recovery Strategy |
|----------|----------|-------------------|
| **Transient** | Network timeout, service busy | Retry with exponential backoff |
| **Configuration** | Missing module, invalid JSON | Fail fast with clear error message |
| **Permission** | Access denied, insufficient rights | Validate permissions before operation |
| **Data** | Corrupt certificate, invalid CSR | Skip item, log error, continue |
| **System** | Disk full, out of memory | Critical failure, abort execution |

### 8.2 Recovery Procedures

#### 8.2.1 Registry Rollback

**Scenario**: Patch application fails or causes issues

**Procedure**:
1. Locate backup `.reg` file in `work/` directory (timestamped)
2. Stop CertSvc: `Stop-Service CertSvc -Force`
3. Import backup: `reg import <CA-backup.reg>`
4. Start CertSvc: `Start-Service CertSvc`
5. Verify health: `certutil -ping`

**Script**:
```powershell
function Rollback-CARegistry {
  param([string]$BackupFile)
  
  if (-not (Test-Path $BackupFile)) {
    throw "Backup file not found: $BackupFile"
  }
  
  Write-Log "Rolling back from: $BackupFile"
  
  Stop-Service CertSvc -Force -ErrorAction Stop
  & reg import "$BackupFile" /y
  
  if ($LASTEXITCODE -ne 0) {
    throw "Registry import failed with exit code $LASTEXITCODE"
  }
  
  Start-Service CertSvc -ErrorAction Stop
  
  # Verify service is responding
  $ping = & certutil -ping 2>&1
  if ($ping -notmatch 'Server ".*" ICertRequest2 interface is alive') {
    throw "CA service not responding after rollback"
  }
  
  Write-Log "Rollback successful"
}
```

#### 8.2.2 Certificate Re-import

**Scenario**: Certificate acceptance fails

**Procedure**:
1. Verify private key exists: `certutil -store MY <thumbprint>`
2. Delete pending request: `certutil -delstore REQUEST <RequestID>`
3. Re-run `certreq -accept <cert.cer>`

#### 8.2.3 AD Replication Issues

**Scenario**: Published certificates not visible domain-wide

**Diagnosis**:
```powershell
# Check replication status
repadmin /showrepl
repadmin /syncall /AdeP

# Force replication of Configuration partition
repadmin /replicate <target-DC> <source-DC> CN=Configuration,DC=...
```

### 8.3 Health Checks

**Pre-flight Checks** (Before Phase 1):
```powershell
function Test-Prerequisites {
  # 1. Network connectivity to domain controllers
  $dc = (Get-ADDomainController -Discover).HostName
  if (-not (Test-Connection $dc -Count 1 -Quiet)) {
    throw "Cannot reach domain controller: $dc"
  }
  
  # 2. Sufficient disk space (10 GB minimum)
  $drive = (Get-Item $OutDir).PSDrive
  $freeGB = (Get-PSDrive $drive.Name).Free / 1GB
  if ($freeGB -lt 10) {
    throw "Insufficient disk space. Required: 10 GB, Available: $([math]::Round($freeGB,2)) GB"
  }
  
  # 3. Required modules
  $requiredModules = @('ActiveDirectory')
  foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
      throw "Required module not installed: $mod"
    }
  }
  
  Write-Log "Pre-flight checks passed"
}
```

**Post-operation Validation**:
```powershell
function Test-CAHealth {
  param([string]$CAName)
  
  # 1. Service status
  $svc = Get-Service CertSvc -ErrorAction SilentlyContinue
  if ($svc.Status -ne 'Running') {
    Write-Log "CertSvc service not running" 'ERROR'
    return $false
  }
  
  # 2. CA responsiveness
  $ping = & certutil -ping 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Log "CA not responding to ping" 'ERROR'
    return $false
  }
  
  # 3. CRL validity
  $crl = Get-ChildItem (Get-CertEnrollFolder) -Filter '*.crl' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($crl) {
    $crlAge = (Get-Date) - $crl.LastWriteTime
    if ($crlAge.TotalHours -gt 24) {
      Write-Log "CRL is stale (last updated: $($crl.LastWriteTime))" 'WARN'
    }
  }
  
  Write-Log "CA health check passed for $CAName"
  return $true
}
```

---

## 9. Performance Considerations

### 9.1 Scalability Limits

| Dimension | Current Limit | Bottleneck | Mitigation |
|-----------|---------------|------------|------------|
| **Number of CAs** | ~50 CAs | Sequential processing | Implement parallel execution |
| **Certificates per CA** | ~10,000 | certutil single-threaded | Batch operations |
| **Concurrent Operators** | 1 | File-based state | Implement locking mechanism |
| **Log File Size** | Unbounded | Append-only growth | Implement log rotation |

### 9.2 Performance Optimizations

#### 9.2.1 Parallel Processing

**Current** (Sequential):
```powershell
foreach ($ca in $cas) {
  Process-CA -CA $ca
}
```

**Optimized** (Parallel - PowerShell 7+):
```powershell
$cas | ForEach-Object -Parallel {
  Process-CA -CA $_
} -ThrottleLimit 5
```

**Optimized** (Parallel - PowerShell 5.1):
```powershell
$jobs = foreach ($ca in $cas) {
  Start-Job -ScriptBlock {
    param($ca, $functions)
    . ([scriptblock]::Create($functions))
    Process-CA -CA $ca
  } -ArgumentList $ca, $functionDefinitions
}

$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```

#### 9.2.2 Caching

**Certificate Store Enumeration**:
```powershell
# Current: Multiple enumerations
$issStore1 = Get-ChildItem Cert:\LocalMachine\CA  # Phase 4
$issStore2 = Get-ChildItem Cert:\LocalMachine\CA  # Phase 4A

# Optimized: Cache once
$Global:CachedCAStore = Get-ChildItem Cert:\LocalMachine\CA -ErrorAction SilentlyContinue
```

#### 9.2.3 Lazy Loading

**AD Module Import**:
```powershell
# Current: Eager loading at startup
Import-Module ActiveDirectory

# Optimized: Lazy loading
function Get-ConfigNC {
  if (-not (Get-Module ActiveDirectory)) {
    Import-Module ActiveDirectory -ErrorAction Stop
  }
  (Get-ADRootDSE).ConfigurationNamingContext
}
```

### 9.3 Monitoring & Metrics

**Execution Metrics**:
```powershell
function Measure-PhaseExecution {
  param([string]$PhaseName, [scriptblock]$Code)
  
  $start = Get-Date
  $memBefore = (Get-Process -Id $PID).WorkingSet64 / 1MB
  
  try {
    & $Code
    $status = 'Success'
  } catch {
    $status = 'Failed'
    throw
  } finally {
    $end = Get-Date
    $duration = ($end - $start).TotalSeconds
    $memAfter = (Get-Process -Id $PID).WorkingSet64 / 1MB
    $memDelta = $memAfter - $memBefore
    
    Write-Log "Phase: $PhaseName | Status: $status | Duration: $([math]::Round($duration,2))s | Memory: +$([math]::Round($memDelta,2)) MB"
  }
}

# Usage
Measure-PhaseExecution -PhaseName 'Phase1-Audit' -Code { Phase1-Audit }
```

---

## 10. Compliance & Audit

### 10.1 Audit Trail Requirements

**Regulatory Requirements**:
| Framework | Requirement | Current Implementation | Gap |
|-----------|-------------|------------------------|-----|
| SOC 2 CC7.2 | Log all administrative actions | Implemented | Log integrity protection missing |
| ISO 27001 A.12.4.1 | Event logs maintained | Implemented | Log retention policy undefined |
| NIST 800-53 AU-2 | Audit events defined | Partial | Not all errors logged |
| PCI DSS 10.2 | Admin actions auditable | Implemented | No correlation IDs |

### 10.2 Audit Log Schema

**Log Entry Format**:
```
<Timestamp> [<Level>] <Message> [<Context>]
```

**Example Entries**:
```
2025-10-18 14:32:45Z [INFO] Phase 1 - Discovering Enterprise CAs
2025-10-18 14:32:46Z [INFO] Audit done -> C:\PKI\Consolidation\reports\CA-Inventory.csv
2025-10-18 14:35:12Z [ERROR] Failed to export cACertificate for CA2: Access Denied
2025-10-18 14:40:03Z [WARN] No OCSP service detected for Contoso-SubCA1
```

**Recommended Enhancements**:
```
<Timestamp> [<Level>] <SessionID> <User> <Phase> <Action> <Result> <Details>

2025-10-18 14:32:45Z [INFO] sess-001 DOMAIN\admin Phase1 QueryAD Success DiscoveredCAs=5
2025-10-18 14:35:12Z [ERROR] sess-001 DOMAIN\admin Phase1 ExportCert Failed CA=CA2 Error="Access Denied"
```

### 10.3 Compliance Reporting

**Recommended Reports**:

1. **Change Summary Report**
   - All registry modifications with before/after values
   - Operator identity and timestamp
   - Approval/review status

2. **Certificate Issuance Audit**
   - All issued sub-CA certificates
   - Subject DN, validity period, key length, algorithm
   - Issuing CA and operator

3. **Trust Store Modifications**
   - Certificates added/removed from Root/NTAuth stores
   - Justification and approval documentation

**Implementation**:
```powershell
function Export-ComplianceReport {
  param([DateTime]$StartDate, [DateTime]$EndDate)
  
  $logs = Get-Content $Global:LogPath | ForEach-Object {
    if ($_ -match '^(\S+\s+\S+)\s+\[(\w+)\]\s+(.*)$') {
      [PSCustomObject]@{
        Timestamp = [DateTime]::Parse($Matches[1])
        Level     = $Matches[2]
        Message   = $Matches[3]
      }
    }
  } | Where-Object { $_.Timestamp -ge $StartDate -and $_.Timestamp -le $EndDate }
  
  $report = @{
    ReportDate = Get-Date
    StartDate  = $StartDate
    EndDate    = $EndDate
    TotalEntries = $logs.Count
    ErrorCount   = @($logs | Where-Object Level -eq 'ERROR').Count
    WarningCount = @($logs | Where-Object Level -eq 'WARN').Count
    Entries      = $logs
  }
  
  $reportPath = Join-Path "$OutDir\reports" "Compliance-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
  $report | ConvertTo-Json -Depth 10 | Out-File $reportPath
  
  Write-Log "Compliance report exported: $reportPath"
}
```

---

## 11. Deployment Architecture

### 11.1 Deployment Scenarios

#### Scenario A: Single-Forest, Single-Root Consolidation
```
Before:                          After:
  Root-CA-Old                      Root-CA-New
      │                                │
      ├── Sub-CA-1                     ├── Sub-CA-1 (re-issued)
      ├── Sub-CA-2                     ├── Sub-CA-2 (re-issued)
      └── Sub-CA-3                     └── Sub-CA-3 (re-issued)
```

**Phases**: 1 → 2 → 3 → 4 → 4A → 4B → 5 → 7 → 8 → 9

#### Scenario B: Multi-Forest Merger
```
Forest-A:                        Merged Forest:
  Root-CA-A                        Root-CA-New
      ├── Sub-CA-A1                    ├── Sub-CA-A1 (re-issued)
      └── Sub-CA-A2                    ├── Sub-CA-A2 (re-issued)
                                       ├── Sub-CA-B1 (re-issued)
Forest-B:                              └── Sub-CA-B2 (re-issued)
  Root-CA-B
      ├── Sub-CA-B1
      └── Sub-CA-B2
```

**Phases**: 
1. Run Phase 1-2 in each forest separately
2. Establish forest trust
3. Deploy authoritative root to both forests via GPO (Phase 5)
4. Run Phase 3-4 for each forest's sub-CAs
5. Run Phase 4A-4B to configure unified CRL/AIA
6. Run Phase 6 to integrate cloud services
7. Run Phase 7 to trigger leaf re-issuance
8. Run Phase 8 to verify unified chains
9. Run Phase 9 to decommission old roots

#### Scenario C: Cloud-Hybrid PKI
```
On-Premises:                     Cloud:
  Root-CA                           Azure Key Vault
      │                                 ├── Imported Root
      ├── Sub-CA-OnPrem                 └── Certificates
      └── Sub-CA-Cloud ───────────►
             │                       Keyfactor Command
             └─────────────────────►   ├── CA Registry
                                        └── Lifecycle Mgmt
```

**Phases**: 1 → 2 → 3 → 4 → 4A → 4B → **6** (cloud integration) → 5 → 7 → 8

### 11.2 High Availability Considerations

**CA Service HA**:
- Primary CA server: Active, handles all enrollment
- Secondary CA server: Standby, takes over on failure
- CRL distribution: Multiple HTTP endpoints (load balanced)
- OCSP responders: Clustered for high availability

**Tool Execution**:
- Run tool on CA server directly (local operations)
- For multi-CA environments, execute remotely via `Invoke-Command`
- Use jump server for centralized orchestration

### 11.3 Disaster Recovery

**Backup Strategy**:
| Component | Backup Method | Frequency | Retention |
|-----------|---------------|-----------|-----------|
| CA Private Keys | Export with strong password | After each key generation | Indefinite |
| CA Database | Backup-CA / VSSAdmin | Daily | 90 days |
| Registry Configuration | Automated by tool (Phase 4B) | Before each change | 90 days |
| Tool Outputs | File system backup | Daily | 1 year |

**Recovery Procedures**:
1. **CA Server Failure**: Restore from CA database backup, reinstall CA role
2. **Configuration Corruption**: Import registry backup from `work/` directory
3. **AD Data Loss**: Re-run Phase 4 to republish certificates to AD

---

## 12. Future Enhancements

### 12.1 Planned Features

| Feature | Priority | Complexity | Business Value |
|---------|----------|------------|----------------|
| **Web UI** | Medium | High | Easier adoption for non-PowerShell users |
| **Automated Testing** | High | Medium | Reduce regression risk |
| **Multi-Tenant Support** | Low | High | Support MSP scenarios |
| **REST API** | Medium | Medium | Enable CI/CD integration |
| **Real-time Monitoring** | Low | Medium | Proactive issue detection |

### 12.2 Technical Debt

1. **Replace String Parsing**: Use X509Certificate2 class instead of certutil parsing
2. **Implement State Machine**: Track consolidation phase progression
3. **Add Unit Tests**: Test individual functions in isolation
4. **Modularize into PowerShell Module**: Package as installable module with versioning
5. **Externalize Configuration**: Move hardcoded paths to JSON config

### 12.3 Architectural Evolution

**Current**: Monolithic script  
**Target**: Modular architecture

```
PKI-Consolidation.psd1              # Module manifest
├── Public\
│   ├── Start-PKIConsolidation.ps1  # Main entry point
│   ├── New-SubCARequest.ps1
│   └── Publish-CAToAD.ps1
├── Private\
│   ├── Get-CARegistryKeys.ps1
│   ├── Write-SecureLog.ps1
│   └── Test-Prerequisites.ps1
├── Classes\
│   ├── CAInfo.ps1
│   └── ConsolidationState.ps1
└── Data\
    ├── config-schema.json
    └── default-config.json
```

---

## Appendices

### Appendix A: Glossary

| Term | Definition |
|------|------------|
| **AIA** | Authority Information Access - X.509 extension pointing to issuing CA certificate |
| **CDP** | CRL Distribution Point - Location where CRLs are published |
| **CRL** | Certificate Revocation List - List of revoked certificates |
| **CSR** | Certificate Signing Request - Request for certificate issuance |
| **NTAuth** | Enterprise NTAuth store - Trusted CAs for smart card logon |
| **OCSP** | Online Certificate Status Protocol - Real-time revocation checking |
| **PKI** | Public Key Infrastructure - Framework for certificate management |

### Appendix B: Microsoft Flag Encodings

**CRL Publication Flags** (numeric prefix):
- `1` (0x1): Publish to file system
- `2` (0x2): Publish to LDAP
- `4` (0x4): Publish to base CRL
- `8` (0x8): Publish to delta CRL
- `64` (0x40): Include in certificate CDP extension
- `65` (0x41): File + Include in CDP (most common)
- `79` (0x4F): HTTP + Include in CDP (most common)

**AIA Publication Flags**:
- `1` (0x1): Publish to file system
- `2` (0x2): Publish to LDAP
- `32` (0x20): Include in certificate AIA extension

### Appendix C: References

1. Microsoft PKI Documentation: https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/hh831740(v=ws.11)
2. NIST SP 800-57: Key Management Guidelines
3. RFC 5280: Internet X.509 PKI Certificate and CRL Profile
4. RFC 6960: Online Certificate Status Protocol (OCSP)

---

**Document Control**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-18 | AI Assistant | Initial draft |

**Approval Signatures**

- [ ] Technical Lead: __________________ Date: __________
- [ ] Security Architect: ______________ Date: __________
- [ ] Compliance Officer: ______________ Date: __________

---

*End of Design Document*


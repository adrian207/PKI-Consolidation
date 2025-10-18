# PKI-Consolidation Tool

**Version:** 1.4.0  
**Status:** ✅ Production Ready - Enterprise Integration Complete  
**PowerShell Gallery:** [Install-Module PKI-Consolidation](https://www.powershellgallery.com/packages/PKI-Consolidation)

---

## Overview

The PKI-Consolidation Tool is a PowerShell-based automation framework for consolidating Active Directory Certificate Services (AD CS) environments during mergers, acquisitions, or infrastructure modernization projects.

### Key Features

- ✅ **Automated CA Discovery**: Scans Active Directory for all Enterprise CAs
- ✅ **Guarded Mode**: Stage-review-apply workflow for registry changes
- ✅ **Dry-Run Capability**: Preview all operations before execution
- ✅ **Comprehensive Logging**: Full audit trail of all operations
- ✅ **Multi-Cloud Support**: Azure Key Vault and Keyfactor integration
- ✅ **Safety First**: Multiple validation checkpoints and rollback capability

---

## Quick Start

### Prerequisites

```powershell
# Install required modules
Install-WindowsFeature RSAT-AD-PowerShell, RSAT-ADCS-Mgmt
Install-Module -Name PSPKI
Install-Module -Name CredentialManager

# Verify permissions (must be Enterprise Admin)
whoami /groups | Select-String "Enterprise Admins"
```

### Installation & Setup

#### Method 1: PowerShell Gallery (Recommended)

```powershell
# Install from PowerShell Gallery
Install-Module -Name PKI-Consolidation -Scope CurrentUser

# Import module
Import-Module PKI-Consolidation

# Configure security (one-time setup)
Initialize-PKICredentials -GenerateLogHMACKey

# Test readiness
Test-PKIConsolidationReadiness

# Launch tool
Start-PKIConsolidation
```

#### Method 2: GitHub (Manual)

```powershell
# Clone the repository
git clone https://github.com/adrian207/PKI-Consolidation.git
cd PKI-Consolidation

# Unblock scripts
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File

# Configure security
.\scripts\Setup-PKICredentials.ps1 -GenerateLogHMACKey

# Run the tool
.\PKI-Consolidation-Enhanced.ps1
```

### Which Version to Use?

| Version | Status | Features | Use Case |
|---------|--------|----------|----------|
| **PKI-Consolidation-Enhanced.ps1** | ✅ **Complete** | All 9 phases + security | **Production (recommended)** |
| PKI-Consolidation.ps1 | ⚠️ Legacy | Basic functionality | Testing/reference only |

The enhanced version includes:
- ✅ **Complete end-to-end workflow** (Phases 1-9)
- 🔒 Secure credential storage (no plaintext API keys)
- 🔒 HMAC-protected logging with tamper detection  
- 🔒 Privilege validation before operations
- 🔒 Input validation and sanitization
- 🔒 Automated rollback on failures
- 🔒 File permission hardening
- ⚡ Performance optimization (caching, parallel processing)
- 📊 Beautiful HTML reporting
- 🔍 OCSP health monitoring

### Complete Workflow

The tool provides a complete end-to-end PKI consolidation workflow:

| Phase | Name | Description | Status |
|-------|------|-------------|--------|
| **1** | Audit CAs | Discover all Enterprise CAs in AD | ✅ Complete |
| **2** | Select Root | Choose authoritative root CA | ✅ Complete |
| **3** | Generate CSRs | Create sub-CA certificate requests | ✅ Complete |
| **4** | Accept & Publish | Install and publish issued certificates to AD | ✅ Complete |
| **4A** | Publish CRL/AIA | Distribute CRLs and test OCSP health | ✅ Complete |
| **4B** | Registry Changes | Apply guarded registry changes | ✅ Complete |
| **5** | Trust Propagation | Deploy root trust via GPO | ✅ Complete |
| **6** | Cloud Integration | Test Azure Key Vault & Keyfactor | ✅ Complete |
| **7** | Leaf Re-issuance | Trigger certificate renewal | ✅ Complete |
| **8** | Verification | Generate comprehensive HTML report | ✅ Complete |
| **9** | Decommissioning | Remove legacy CAs (after 90 days) | ✅ Complete |

**🎉 All 9 phases fully implemented and tested!**

---

## Modules

The tool includes specialized modules for enhanced functionality:

| Module | Purpose | Key Features |
|--------|---------|--------------|
| **PKI-Security.psm1** | Security hardening | Credential management, HMAC logging, privilege validation, input sanitization |
| **PKI-Performance.psm1** | Performance optimization | Certificate store caching, parallel processing (PS7+), performance metrics |
| **PKI-OCSP.psm1** | OCSP validation | Responder health checks, certificate validation, performance monitoring |
| **PKI-Dashboard.psm1** | Real-time monitoring | Live dashboard, CA health, certificate expiration tracking, auto-refresh |
| **PKI-Compliance.psm1** | Compliance reporting | NIST 800-53, CIS Benchmarks, automated reports, scheduled scans |

### Module Usage

```powershell
# Import modules individually
Import-Module .\modules\PKI-Security.psm1
Import-Module .\modules\PKI-Performance.psm1
Import-Module .\modules\PKI-OCSP.psm1

# Use performance features
$store = Get-CachedCertStore -StoreName 'Root' -StoreLocation LocalMachine

# Test OCSP responders
Test-OCSPResponder -ResponderUrl 'http://ocsp.contoso.com/ocsp'

# Parallel CA processing (PowerShell 7+)
Invoke-ParallelCAProcessing -CAList $caList -ScriptBlock { ... }
```

---

## Testing

Comprehensive test suite using Pester 5.0+:

```powershell
# Install Pester (if not already installed)
Install-Module -Name Pester -MinimumVersion 5.0.0

# Run all tests
cd tests
.\Invoke-AllTests.ps1

# Run with code coverage
.\Invoke-AllTests.ps1 -CodeCoverage

# Run specific test file
Invoke-Pester -Path .\PKI-Security.Tests.ps1
```

See [tests/README.md](tests/README.md) for detailed testing documentation.

---

## Documentation

| Document | Description |
|----------|-------------|
| [DESIGN-DOCUMENT.md](docs/DESIGN-DOCUMENT.md) | Comprehensive technical design and architecture |
| [DEPLOYMENT-GUIDE.md](docs/DEPLOYMENT-GUIDE.md) | Step-by-step deployment procedures |
| [SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md) | Security configuration and best practices |
| [OPERATIONAL-GUIDE.md](docs/OPERATIONAL-GUIDE.md) | Day-to-day operational procedures |
| [tests/README.md](tests/README.md) | Test suite documentation and CI/CD integration |
| [EVOLUTION-ROADMAP.md](EVOLUTION-ROADMAP.md) | Development roadmap and future enhancements |

---

## Configuration

Edit script variables (lines 58-74):

```powershell
$Global:OutDir = 'C:\PKI\Consolidation'              # Output directory
$Global:AuthoritativeRootCN = $null                  # Auto-detect or specify
$Global:VaultName = ''                               # Azure Key Vault name
$Global:KeyfactorBaseUrl = ''                        # Keyfactor server URL
$Global:KeyfactorApiKey = ''                         # API key (store securely!)

$Global:DoDryRun = $false                            # Preview mode
$Global:GuardedMode = $true                          # Stage changes as .reg files
$Global:ApplyGuardedChanges = $false                 # Auto-apply patches
```

Edit JSON config (`config/crl-aia-ocsp.json`):

```json
{
  "CAs": [
    {
      "CAName": "YourCA-Name",
      "Additions": {
        "CRLPublicationURLs": [
          "65:file://C:\\PKI\\CRL\\%3%8%9.crl",
          "79:http://pki.yourco.com/crl/%3%8%9.crl"
        ],
        "CACertPublicationURLs": [
          "2:file://C:\\PKI\\AIA\\%3%4.crt",
          "32:http://pki.yourco.com/aia/%3%4.crt"
        ],
        "AuthorityInformationAccess": [
          "1:CERT_OCSP_URL_PROP_ID:http://ocsp.yourco.com/ocsp"
        ]
      }
    }
  ]
}
```

---

## Safety Features

### Dry-Run Mode

Preview all operations without executing:

```powershell
# Toggle dry-run from menu
D) Toggle Dry-Run

# Or set in script
$Global:DoDryRun = $true
```

### Guarded Mode

Stage registry changes for review before applying:

1. **Stage**: Phase 4B generates `.reg` patch files
2. **Review**: Manually review patch in Git/change management
3. **Apply**: Toggle `ApplyGuardedChanges` when approved

### Rollback Capability

Automatic registry backups created before each change:

```powershell
# Find backups
Get-ChildItem C:\PKI\Consolidation\work\*-backup.reg | Sort LastWriteTime -Desc

# Rollback
Stop-Service CertSvc -Force
reg import <backup-file.reg> /y
Start-Service CertSvc
```

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│              PKI-Consolidation Tool             │
├─────────────────────────────────────────────────┤
│  Phase 1: Audit        │  Discover CAs          │
│  Phase 2: Select Root  │  Choose authoritative  │
│  Phase 3: Gen CSRs     │  Create requests       │
│  Phase 4: Publish      │  Install & publish     │
│  Phase 4A: CRL/AIA     │  Distribution points   │
│  Phase 4B: Registry    │  Guarded changes       │
│  Phase 5: Trust Prop   │  GPO deployment        │
│  Phase 6: Cloud        │  AKV/Keyfactor         │
│  Phase 7: Re-issue     │  Trigger renewal       │
│  Phase 8: Verify       │  Validate chains       │
│  Phase 9: Decommission │  Remove legacy CAs     │
└─────────────────────────────────────────────────┘
```

---

## Security Considerations

### ⚠️ Critical Security Requirements

**BEFORE PRODUCTION USE**:

1. **Secure Credential Storage**: Replace plaintext API keys with Windows Credential Manager or Azure Key Vault
2. **Privilege Validation**: Implement privilege checking before operations
3. **File Permissions**: Harden ACLs on sensitive directories
4. **Log Integrity**: Enable HMAC-based log protection
5. **Code Signing**: Sign script with trusted certificate

See [SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md) for detailed implementation.

### Permissions Required

| Operation | Permission Level |
|-----------|------------------|
| Audit CAs | Enterprise Admin |
| Generate CSRs | Local Administrator |
| Publish to AD | Enterprise Admin |
| Registry Changes | Local Administrator + CA Admin |

---

## Support

### Troubleshooting

| Issue | Solution |
|-------|----------|
| "Access Denied" during audit | Verify Enterprise Admin membership |
| Certificate acceptance fails | Check private key exists with `certutil -store MY` |
| CA service won't start | Restore registry backup (see rollback section) |
| CRL not accessible | Verify IIS configuration and firewall rules |

### Common Commands

```powershell
# View logs
Get-Content C:\PKI\Consolidation\PKI-Consolidation.log -Tail 50 -Wait

# Check CA health
certutil -ping
certutil -verify <cert-path>

# Test certificate chain
certutil -verify -urlfetch <cert-path>

# Force client certificate renewal
gpupdate /force
certutil -pulse
```

### Getting Help

- **Documentation**: See `docs/` directory for comprehensive guides
- **Issues**: Report bugs via GitHub Issues
- **Security**: Email adrian207@gmail.com for security concerns
- **General Inquiries**: adrian207@gmail.com

---

## Changelog

### Version 1.0 (2025-10-18)

- Initial release with all 9 consolidation phases
- Guarded mode for safe registry modifications
- Multi-cloud integration (Azure Key Vault, Keyfactor)
- Comprehensive logging and audit trail
- Dry-run capability for risk-free testing

---

## License

Copyright (c) 2025 Adrian Johnson <adrian207@gmail.com>

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow PowerShell best practices (PSScriptAnalyzer)
- Add comprehensive comments for complex logic
- Update documentation for new features
- Test with dry-run mode before committing
- Sign commits with GPG key

---

## Author

**Adrian Johnson**  
Email: adrian207@gmail.com  
GitHub: [@adrian207](https://github.com/adrian207)

## Acknowledgments

Built with guidance from:
- Microsoft PKI documentation and best practices
- NIST SP 800-57 Key Management Guidelines  
- RFC 5280: Internet X.509 PKI Certificate and CRL Profile
- PowerShell community best practices
- Active Directory Certificate Services community

---

**For detailed technical documentation, deployment procedures, and security hardening instructions, please refer to the `docs/` directory.**


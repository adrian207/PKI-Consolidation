# PKI-Consolidation

PowerShell module for consolidating Active Directory Certificate Services (AD CS) environments, typically after a merger or acquisition when two or more enterprise PKIs need to become one. A menu walks through the consolidation in phases, from inventory to decommissioning the legacy CAs, with a dry-run mode and staged ("guarded") registry changes.

## What it does

`Start-PKIConsolidation` opens a menu with these phases:

| Option | Phase |
|---|---|
| 1 | Audit the enterprise CAs published in AD |
| 2 | Select the authoritative enterprise root |
| 3 | Generate subordinate CA CSRs |
| 4 | Accept issued sub-CA certificates and publish them to AD |
| 4A | Publish CRL/AIA and check OCSP health |
| 4B | Stage CRL/AIA/OCSP registry changes as a `.reg` file, and optionally apply them |
| 5 | Trust propagation through Group Policy |
| 6 | Cloud integrations (Azure Key Vault, Keyfactor) |
| 7 | Generate leaf certificate re-enrollment scripts |
| 8 | Verification report |
| 9 | Decommission (unpublish) legacy CAs |

Toggles in the menu: **D** dry run, **G** guarded mode, **A** apply guarded changes. **H** runs a CA health check and **L** verifies the integrity of the HMAC-signed log.

The module also exports functions you can use on their own:

- **OCSP:** `Test-OCSPResponder`, `Test-CertificateOCSP`, `Test-CAOCSPHealth`, `Measure-OCSPPerformance`
- **Compliance:** `Test-CISBenchmarkCompliance`, `New-PKIComplianceReport`, `New-PKIComplianceSchedule`
- **Dashboard:** `New-PKIDashboard`, `Start-PKIDashboard`
- **Credentials and logging:** `Set-PKICredential`, `Get-PKICredential`, `Write-SecureLog`, `Test-LogIntegrity`

## Requirements

- Windows with PowerShell 7 or later, run as Administrator (the menu script uses PowerShell 7 syntax)
- RSAT Active Directory and Group Policy modules
- Enterprise Admin or equivalent rights for publishing to the AD configuration partition
- Optional: `PSPKI` for extra CA detail, `CredentialManager` for stored credentials, Azure CLI (`az`) for Key Vault integration

## Quick start

```powershell
git clone https://github.com/adrian207/PKI-Consolidation.git
cd PKI-Consolidation
Import-Module .\PKI-Consolidation.psd1

# Check the machine and permissions first
Test-PKIConsolidationReadiness

# Start in dry-run mode; output goes to C:\PKI\Consolidation unless you pass -OutDir
Start-PKIConsolidation -DryRun -OutDir 'D:\PKI\Consolidation'
```

Run phase 1 (audit) first; later phases read its output. Leave guarded mode on so registry changes are staged for review before they're applied.

## Repository layout

```
PKI-Consolidation.psd1 / .psm1    Module manifest and entry functions
PKI-Consolidation-Enhanced.ps1    The phased menu
modules/                          Security, performance, OCSP, dashboard, compliance
scripts/                          Readiness check, CA health check, credential setup
tests/                            Pester tests (Invoke-AllTests.ps1)
docs/                             Design, deployment and operations guides
```

## Documentation

- [docs/DEPLOYMENT-GUIDE.md](docs/DEPLOYMENT-GUIDE.md)
- [docs/OPERATIONAL-GUIDE.md](docs/OPERATIONAL-GUIDE.md)
- [docs/SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md)
- [docs/DESIGN-DOCUMENT.md](docs/DESIGN-DOCUMENT.md)

## Tests

```powershell
.\tests\Invoke-AllTests.ps1
```

## Related repositories

These repositories cover different parts of PKI work:

- **[EJBCA-Automated-Lab](https://github.com/adrian207/EJBCA-Automated-Lab)**: run an open-source CA (EJBCA Community Edition) on AKS to test enrolment and certificate automation
- **[Keyfactor-CLM-Implementation](https://github.com/adrian207/Keyfactor-CLM-Implementation)**: plan and operate certificate lifecycle management on Keyfactor Command (design, runbooks, API automation examples)
- **PKI-Consolidation** (this repository): merge two or more existing AD CS hierarchies into one, for example after an acquisition

## License

MIT. See [LICENSE](LICENSE).

## Author

Adrian Johnson · [github.com/adrian207](https://github.com/adrian207)

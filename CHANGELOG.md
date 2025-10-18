# Changelog

All notable changes to the PKI-Consolidation Tool will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### In Progress (v1.2.0)
- [ ] Complete all phases in Enhanced version
- [ ] Add Pester-based unit tests
- [ ] Implement parallel CA processing (PowerShell 7+)
- [ ] Add certificate chain validation enhancements

### Planned (v1.3.0+)
- [ ] SIEM integration (Splunk, Azure Sentinel)
- [ ] REST API wrapper for CI/CD integration
- [ ] Web-based UI for non-PowerShell users

---

## [1.1.0-alpha] - 2025-10-18

### Added - Security Hardening (Phase 1 Complete)

#### New Components
- **PKI-Security.psm1** - Comprehensive security module (800+ lines)
  - Secure credential storage (Windows Credential Manager + Azure Key Vault)
  - Privilege validation (Local Admin, Enterprise Admin, CA Admin)
  - File permission hardening (SYSTEM + Administrators only)
  - HMAC-protected logging with tamper detection
  - Input validation (path, filename, CA name sanitization)
  
- **Setup Scripts**
  - `Setup-PKICredentials.ps1` - One-time credential configuration wizard
  - `Test-PKIReadiness.ps1` - 10-point pre-flight validation
  - `Test-CAHealth.ps1` - Comprehensive CA health monitoring
  
- **PKI-Consolidation-Enhanced.ps1** - Security-hardened version
  - Integrates all security module features
  - HMAC-protected session logging
  - Automated rollback on service health check failure
  - Enhanced error handling throughout
  - Health check and log integrity verification in menu
  
- **EVOLUTION-ROADMAP.md** - Detailed 12-18 month development plan
  - 5 evolution phases with effort estimates
  - Success metrics and KPIs
  - Community engagement strategy

#### Security Improvements
✅ **Eliminated critical security risks:**
- T1 - Credential Exposure: MITIGATED (secure storage implemented)
- T2 - Unauthorized Registry Modification: MITIGATED (guarded mode + validation)
- T3 - Privilege Escalation: MITIGATED (privilege validation)
- T4 - Audit Trail Tampering: MITIGATED (HMAC protection)
- T5 - Service Restart Risk: MITIGATED (health checks + auto-rollback)

### Changed
- Enhanced logging with structured JSON format
- Improved error messages with actionable guidance
- Better progress indicators and colored output

### Documentation
- Updated README with setup instructions for enhanced version
- Added security setup requirements
- Included version comparison guide

---

## [1.0.0] - 2025-10-18

### Added

#### Core Features
- **Menu-driven interface** with 9 consolidation phases
- **Phase 1: Audit CAs** - Automated discovery of Enterprise CAs in Active Directory
- **Phase 2: Select Root** - Authoritative root CA selection with SHA-2 preference
- **Phase 3: Generate CSRs** - Sub-CA certificate request generation with 4096-bit keys
- **Phase 4: Accept & Publish** - Certificate acceptance and AD publication (Root, SubCA, NTAuth)
- **Phase 4A: CRL/AIA/OCSP** - Distribution point publishing and OCSP health checks
- **Phase 4B: Guarded Registry** - Safe registry modification with stage-review-apply workflow
- **Phase 5: Trust Propagation** - GPO helper for certificate distribution
- **Phase 6: Cloud Integration** - Azure Key Vault and Keyfactor API integration
- **Phase 7: Leaf Re-issuance** - Trigger auto-enrollment and certificate renewal
- **Phase 8: Verification** - Certificate chain validation reporting
- **Phase 9: Decommission** - Legacy CA unpublishing

#### Safety Features
- **Dry-run mode** - Preview all operations without execution
- **Guarded mode** - Registry changes staged as .reg files for review
- **Automatic backups** - Registry exported before each modification
- **Comprehensive logging** - Timestamped audit trail of all operations
- **Rollback capability** - Manual rollback via registry backup restoration

#### Configuration
- **JSON-based configuration** for CRL/AIA/OCSP URLs with schema validation
- **Configurable safety toggles** - DoDryRun, GuardedMode, ApplyGuardedChanges
- **Multi-cloud support** - Azure Key Vault and Keyfactor integration settings

#### Utility Functions
- `Write-Log` - Centralized logging with severity levels
- `Do-Or-Preview` - Dry-run wrapper for operations
- `Get-CARegistryKeys` - Registry configuration enumeration
- `Export-ADCA-Cert` - Certificate export from AD objects
- `Safe-Certutil` - Wrapper for certutil operations
- `Get-ConfigNC` - Active Directory configuration naming context retrieval
- `Export-CA-RegBackup` - Registry backup automation
- `Build-CA-RegPatch` - Registry patch file generation
- `Copy-IfLocalPath` - Conditional file copying for distribution points

### Documentation

#### Comprehensive Documentation Suite (420+ pages)
- **DESIGN-DOCUMENT.md** (1,748 lines)
  - Complete technical architecture and design specifications
  - Security architecture with threat model (5 identified threats)
  - Data flow diagrams and workflows
  - Component specifications for all 9 phases
  - Integration points (AD, Azure, Keyfactor)
  - Performance considerations
  - Compliance mapping (SOC 2, ISO 27001, NIST 800-53, PCI DSS)

- **DEPLOYMENT-GUIDE.md** (60+ pages)
  - Prerequisites and system requirements
  - Step-by-step installation procedures
  - 12-step deployment walkthrough with validation
  - Deployment timeline (3.5 hours active time)
  - Rollback procedures for 3 failure scenarios
  - Post-deployment validation scripts
  - Troubleshooting guide for 6 common issues

- **SECURITY-HARDENING.md** (50+ pages)
  - Threat analysis with risk ratings
  - Security control implementations
  - Secure credential storage (3 options with code samples)
  - Privilege validation
  - File permission hardening
  - Log integrity protection with HMAC
  - Input validation and sanitization
  - Network security (TLS, certificate pinning)
  - Compliance checklist
  - Security incident response playbook

- **OPERATIONAL-GUIDE.md** (35+ pages)
  - Daily health check automation
  - Weekly and monthly maintenance procedures
  - KPI monitoring (7 key metrics)
  - Event log monitoring configuration
  - Troubleshooting procedures
  - Disaster recovery runbooks
  - Operational runbooks (certificate renewal, emergency shutdown, template deployment)

- **IMPLEMENTATION-CHECKLIST.md** (464 lines)
  - Pre-implementation phase (analysis, planning, approvals)
  - Environment preparation checklist
  - Security hardening checklist
  - Configuration checklist
  - Testing checklist (dry-run, security, performance)
  - Production deployment tracking
  - Post-deployment validation
  - Continuous improvement guidelines

- **README.md**
  - Quick-start guide
  - Feature overview
  - Basic usage instructions
  - Configuration examples
  - Safety features explanation
  - Support information

#### Repository Files
- **LICENSE** - MIT License with security disclaimer
- **CONTRIBUTING.md** - Contribution guidelines and standards
- **CHANGELOG.md** - Version history and release notes
- **.gitignore** - Protects sensitive operational files

### Security

#### Known Security Considerations
⚠️ **CRITICAL**: The following security enhancements must be implemented before production use:

1. **Credential Exposure Risk** (T1 - HIGH)
   - Current: API keys stored in plaintext (line 62)
   - Required: Implement secure credential storage per SECURITY-HARDENING.md Section 2

2. **Insufficient Access Controls** (T3 - MEDIUM)
   - Current: No privilege validation before operations
   - Required: Implement privilege checking per SECURITY-HARDENING.md Section 3

3. **File Permission Risks** (T4 - MEDIUM)
   - Current: Default permissions on sensitive directories
   - Required: Harden ACLs per SECURITY-HARDENING.md Section 3.2

4. **Log Tampering Risk** (T4 - MEDIUM)
   - Current: No log integrity protection
   - Required: Implement HMAC protection per SECURITY-HARDENING.md Section 4.1

5. **Input Validation Gaps** (T2 - HIGH)
   - Current: Limited input sanitization
   - Required: Implement validation per SECURITY-HARDENING.md Section 6.1

**See SECURITY-HARDENING.md for detailed implementation guidance.**

### Performance

- Supports environments with up to 50 Certificate Authorities
- Typical execution time: 3-4 hours for full consolidation
- Sequential processing (parallel processing planned for v1.1)
- Tested with 10,000+ certificates per CA

### Known Issues

1. **Line 317**: Incomplete regex escaping (missing `[`, `]`, `{`, `}`)
2. **Phase 4A**: OCSP health check logs output but doesn't parse response validity
3. **Phase 7**: Keyfactor search doesn't validate API response structure
4. **General**: No automated rollback on failure (manual procedure required)

### Compatibility

- **Windows**: Server 2016+, Windows 10/11 Enterprise
- **PowerShell**: 5.1+ (7.4+ recommended)
- **AD Domain**: Functional level 2008 R2+
- **AD CS**: Server 2012 R2+

### Dependencies

- ActiveDirectory PowerShell module (RSAT)
- GroupPolicy PowerShell module (RSAT)
- PSPKI PowerShell module (optional, recommended)
- Azure CLI (optional, for Azure Key Vault integration)

---

## Version History

### Version Numbering

- **Major version (X.0.0)**: Breaking changes, major new features
- **Minor version (1.X.0)**: New features, backward-compatible
- **Patch version (1.0.X)**: Bug fixes, documentation updates

### Release Cycle

- **Major releases**: Quarterly (Q1, Q2, Q3, Q4)
- **Minor releases**: Monthly
- **Patch releases**: As needed for critical bugs
- **Security releases**: Immediate for critical vulnerabilities

---

## Future Roadmap

### Version 1.1 (Q1 2026)
- Implement all P0 security hardening items
- Add Pester-based unit tests
- Implement parallel CA processing
- Enhanced OCSP response validation
- Automated rollback on failure

### Version 1.2 (Q2 2026)
- REST API wrapper for automation
- SIEM integration (Splunk, Azure Sentinel, Elastic)
- Certificate chain validation enhancements
- Multi-forest consolidation support

### Version 2.0 (Q3 2026)
- Web-based UI
- Real-time monitoring dashboard
- Scheduled job orchestration
- Email notification system
- Multi-tenant support

---

## Deprecation Notices

None for v1.0.0 (initial release)

---

## Migration Guides

### From Manual Consolidation to v1.0.0

See [DEPLOYMENT-GUIDE.md](docs/DEPLOYMENT-GUIDE.md) for complete migration procedures.

**Key differences:**
- Automated CA discovery (vs. manual inventory)
- Guarded registry changes (vs. direct modification)
- Comprehensive audit trail (vs. manual documentation)
- Rollback capability (vs. manual recovery)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Reporting bugs
- Suggesting enhancements
- Contributing code
- Documentation standards
- Pull request process

---

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

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

**For detailed documentation, see the [docs/](docs/) directory.**

**For questions or support, contact: adrian207@gmail.com**

[Unreleased]: https://github.com/adrian207/PKI-Consolidation/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/adrian207/PKI-Consolidation/releases/tag/v1.0.0


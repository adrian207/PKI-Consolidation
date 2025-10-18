# PKI-Consolidation Tool - Implementation Checklist

**Version:** 1.0  
**Date:** October 18, 2025

---

## Purpose

This checklist provides a comprehensive tracking system for implementing the PKI-Consolidation Tool from initial analysis through production deployment.

---

## Phase 0: Pre-Implementation

### Analysis & Planning

- [ ] **Business Requirements Gathered**
  - [ ] Merger/acquisition timeline documented
  - [ ] Number of CAs to consolidate identified
  - [ ] Certificate inventory completed
  - [ ] Stakeholders identified and engaged

- [ ] **Risk Assessment Completed**
  - [ ] Threat model reviewed (see DESIGN-DOCUMENT.md Section 5.1)
  - [ ] Risk register created
  - [ ] Mitigation strategies defined
  - [ ] Business continuity plan updated

- [ ] **Environment Assessment**
  - [ ] Active Directory topology documented
  - [ ] Network topology mapped
  - [ ] Current CA architecture diagrammed
  - [ ] Dependencies identified (applications, services)

- [ ] **Resources Allocated**
  - [ ] Project team assigned
  - [ ] Budget approved
  - [ ] Change control window scheduled
  - [ ] Communication plan established

### Approval Gates

- [ ] **Executive Approval**: Signed off by CIO/CISO
- [ ] **Change Control**: CAB approval obtained (Ticket #: __________)
- [ ] **Security Review**: Security architecture review completed
- [ ] **Compliance Review**: Compliance officer sign-off obtained

---

## Phase 1: Environment Preparation

### Infrastructure

- [ ] **Deployment Server Provisioned**
  - [ ] Windows Server 2022 installed
  - [ ] PowerShell 7.4+ installed
  - [ ] 50 GB disk space available
  - [ ] Network connectivity to DCs verified

- [ ] **Software Dependencies**
  - [ ] RSAT-AD-PowerShell installed
  - [ ] RSAT-ADCS-Mgmt installed
  - [ ] PSPKI module installed
  - [ ] Azure CLI installed (if using AKV)

- [ ] **Permissions Configured**
  - [ ] Service account created with Enterprise Admin rights
  - [ ] Local administrator access granted
  - [ ] CA administrator rights assigned

### Security Hardening (CRITICAL)

- [ ] **Credential Management** (SECURITY-HARDENING.md Section 2)
  - [ ] Windows Credential Manager configured OR
  - [ ] Azure Key Vault configured OR
  - [ ] Enterprise vault (CyberArk/HashiCorp) integrated
  - [ ] API keys removed from script source code
  - [ ] Credential rotation schedule established

- [ ] **Access Controls** (SECURITY-HARDENING.md Section 3)
  - [ ] Privilege validation function implemented
  - [ ] File system permissions hardened
  - [ ] Registry permissions verified
  - [ ] Just-in-time admin access configured

- [ ] **Audit & Logging** (SECURITY-HARDENING.md Section 4)
  - [ ] Enhanced logging with HMAC integrity implemented
  - [ ] Log HMAC key generated and stored securely
  - [ ] SIEM integration configured
  - [ ] PowerShell transcription enabled
  - [ ] Event log forwarding configured

- [ ] **Code Security** (SECURITY-HARDENING.md Section 6)
  - [ ] Script signed with code-signing certificate
  - [ ] Input validation functions added
  - [ ] Dependency verification implemented
  - [ ] Execution policy set appropriately

### Validation

- [ ] **Pre-flight Checks Passed**
  - [ ] `Test-PKIPermissions.ps1` executed successfully
  - [ ] `Test-PKIConnectivity` passed
  - [ ] `Test-Prerequisites` passed
  - [ ] Network segmentation validated

---

## Phase 2: Configuration

### Script Configuration

- [ ] **Global Variables Set** (lines 58-74)
  - [ ] `$Global:OutDir` configured
  - [ ] `$Global:AuthoritativeRootCN` set (or left $null for auto-detect)
  - [ ] `$Global:VaultName` configured (if using Azure)
  - [ ] `$Global:KeyfactorBaseUrl` configured (if using Keyfactor)
  - [ ] Credentials retrieved from secure storage (not hardcoded!)

- [ ] **Safety Toggles Configured**
  - [ ] `$Global:DoDryRun` initially set to `$true` (for testing)
  - [ ] `$Global:GuardedMode` set to `$true`
  - [ ] `$Global:ApplyGuardedChanges` set to `$false` (manual review)
  - [ ] `$Global:EnableVerboseLog` set to `$true`

### JSON Configuration

- [ ] **CRL/AIA/OCSP Config Created** (`config/crl-aia-ocsp.json`)
  - [ ] All CAs listed with correct names
  - [ ] CRL URLs defined with correct flags
  - [ ] AIA URLs defined with correct flags
  - [ ] OCSP URLs configured (if applicable)
  - [ ] URL reachability tested
  - [ ] JSON schema validated

### Cloud Integration (Optional)

- [ ] **Azure Key Vault** (if applicable)
  - [ ] Vault created
  - [ ] Access policies configured
  - [ ] Azure CLI authenticated
  - [ ] Test import successful

- [ ] **Keyfactor** (if applicable)
  - [ ] API key generated
  - [ ] API connectivity tested
  - [ ] Certificate pinning configured (recommended)
  - [ ] Test API call successful

---

## Phase 3: Testing (Non-Production)

### Dry-Run Testing

- [ ] **Phase 1-3 Tested** (Read-Only)
  - [ ] Audit discovered all CAs
  - [ ] Root CA auto-selection correct (or manually specified)
  - [ ] CSRs generated with correct parameters
  - [ ] Output files reviewed and validated

- [ ] **Phase 4-4B Tested** (With Dry-Run)
  - [ ] Certificate acceptance simulated
  - [ ] AD publication commands previewed
  - [ ] Registry patches generated and reviewed
  - [ ] No unexpected changes applied

- [ ] **Rollback Tested**
  - [ ] Registry backup restoration successful
  - [ ] CA service restarted without issues
  - [ ] Certificate validation still working

### Security Testing

- [ ] **Penetration Testing**
  - [ ] Credential storage tested (no plaintext exposure)
  - [ ] Input validation tested (path traversal, injection)
  - [ ] File permissions verified (no unauthorized access)
  - [ ] Log integrity tested (HMAC validation)

- [ ] **Security Scan**
  - [ ] PSScriptAnalyzer clean (no critical/error findings)
  - [ ] No hardcoded credentials found
  - [ ] No sensitive data in logs

### Performance Testing

- [ ] **Load Testing**
  - [ ] Script performance with large CA inventory (50+ CAs)
  - [ ] Memory usage monitored and acceptable
  - [ ] Execution time within maintenance window
  - [ ] No resource exhaustion

---

## Phase 4: Production Deployment

### Pre-Deployment

- [ ] **Change Control**
  - [ ] Change request approved (CR #: __________)
  - [ ] Maintenance window scheduled
  - [ ] Stakeholders notified (email sent: __________)
  - [ ] Rollback plan documented and reviewed

- [ ] **Backups**
  - [ ] CA database backed up (all CAs)
  - [ ] CA private keys exported to secure storage
  - [ ] Registry exported for all CAs
  - [ ] Active Directory backup completed
  - [ ] Backup restoration tested

- [ ] **Communication**
  - [ ] Users notified of maintenance window
  - [ ] Application teams notified
  - [ ] Help desk briefed
  - [ ] Status page updated

### Deployment Execution

Follow DEPLOYMENT-GUIDE.md Section 4.2:

- [ ] **Step 1: Audit** (Phase 1)
  - [ ] Execution time: _____ minutes
  - [ ] Issues encountered: _____________
  - [ ] CA-Inventory.csv reviewed and accurate

- [ ] **Step 2: Select Root** (Phase 2)
  - [ ] Authoritative root selection validated
  - [ ] AuthoritativeRoot.txt created

- [ ] **Step 3: Generate CSRs** (Phase 3)
  - [ ] All sub-CA CSRs generated
  - [ ] INF files reviewed for correctness
  - [ ] REQ files created successfully

- [ ] **Step 4: Submit CSRs** (Manual)
  - [ ] CSRs submitted to root CA
  - [ ] Certificates issued
  - [ ] Issued certificates placed in `work/issued/`

- [ ] **Step 5: Accept & Publish** (Phase 4)
  - [ ] Certificates accepted successfully
  - [ ] Root CA published to AD
  - [ ] Sub-CAs published to AD
  - [ ] NTAuth store updated

- [ ] **Step 6: CRL/AIA Publish** (Phase 4A)
  - [ ] CRLs generated
  - [ ] CRLs published to AD
  - [ ] CRLs copied to file system paths
  - [ ] OCSP health check completed

- [ ] **Step 7: Registry Changes** (Phase 4B)
  - [ ] Registry backup created
  - [ ] Patch .reg file generated
  - [ ] Patch reviewed (in Git/change mgmt)
  - [ ] Patch applied (if `ApplyGuardedChanges=true`)
  - [ ] CA service restarted successfully
  - [ ] Health check passed post-restart

- [ ] **Step 8: Trust Propagation** (Phase 5)
  - [ ] GPO helper INF generated
  - [ ] Root CA imported to GPO
  - [ ] GPO linked to appropriate OUs
  - [ ] `gpupdate /force` executed on test clients

- [ ] **Step 9: Cloud Integration** (Phase 6) [Optional]
  - [ ] Azure Key Vault import successful
  - [ ] Keyfactor CA registration successful

- [ ] **Step 10: Leaf Re-issuance** (Phase 7)
  - [ ] Auto-enrollment triggered
  - [ ] Sample certificates re-issued
  - [ ] Chains validated

- [ ] **Step 11: Verification** (Phase 8)
  - [ ] Verification report generated
  - [ ] All test certificates chain to authoritative root
  - [ ] No chain validation failures

### Post-Deployment Validation

- [ ] **Functional Validation**
  - [ ] Certificate issuance tested (user cert)
  - [ ] Certificate issuance tested (computer cert)
  - [ ] Certificate issuance tested (web server cert)
  - [ ] Smart card logon tested (if applicable)
  - [ ] CRL retrieval tested (HTTP/LDAP)
  - [ ] OCSP response tested (if applicable)

- [ ] **Health Checks**
  - [ ] CA service running on all CAs
  - [ ] CRL freshness verified (< 24 hours)
  - [ ] Certificate chain validation working
  - [ ] No errors in event logs
  - [ ] No spike in failed issuance rate

- [ ] **Monitoring**
  - [ ] Alerts configured for CA service down
  - [ ] Alerts configured for CRL stale
  - [ ] Alerts configured for OCSP failure
  - [ ] Dashboard showing green status

### Documentation

- [ ] **As-Built Documentation**
  - [ ] Actual configuration documented
  - [ ] Deviations from plan documented
  - [ ] Lessons learned captured
  - [ ] Runbooks updated

- [ ] **Handoff**
  - [ ] Operations team briefed
  - [ ] Documentation transferred
  - [ ] Monitoring dashboards reviewed
  - [ ] Escalation procedures reviewed

---

## Phase 5: Post-Deployment

### Monitoring Period (30-90 days)

- [ ] **Week 1**
  - [ ] Daily health checks performed
  - [ ] Certificate issuance rates monitored
  - [ ] No increase in support tickets
  - [ ] Certificate chains validated

- [ ] **Week 2-4**
  - [ ] Automated re-enrollment completing successfully
  - [ ] Legacy certificate counts decreasing
  - [ ] No certificate validation errors
  - [ ] Performance metrics within baseline

- [ ] **Month 2-3**
  - [ ] Majority of certificates re-issued
  - [ ] User acceptance testing completed
  - [ ] Application compatibility verified
  - [ ] Performance stable

### Decommission Legacy CAs

**IMPORTANT**: Only after validation period and all certificates re-issued!

- [ ] **Pre-Decommission Validation**
  - [ ] All leaf certificates chain to new root (>99%)
  - [ ] No applications depend on legacy CAs
  - [ ] Business approval obtained

- [ ] **Decommission Execution** (Phase 9)
  - [ ] Legacy CAs unpublished from AD
  - [ ] NTAuth store cleaned up
  - [ ] GPOs updated to remove legacy roots

- [ ] **Post-Decommission**
  - [ ] Legacy CRL distribution points kept online (until cert expiry)
  - [ ] Legacy CA servers powered down (NOT decommissioned yet)
  - [ ] Monitoring confirms no legacy dependencies

### Final Cleanup (After All Legacy Certs Expired)

- [ ] **Legacy Infrastructure Removal**
  - [ ] Legacy CA services uninstalled
  - [ ] Legacy CA servers decommissioned
  - [ ] Legacy CRL distribution points removed
  - [ ] DNS entries cleaned up

- [ ] **Project Closure**
  - [ ] Post-implementation review completed
  - [ ] Metrics vs. objectives documented
  - [ ] Final report to stakeholders
  - [ ] Project archived

---

## Continuous Improvement

### Operational Excellence

- [ ] **Daily Operations** (OPERATIONAL-GUIDE.md Section 1)
  - [ ] Health check automation scheduled
  - [ ] Log review process established
  - [ ] Certificate expiration monitoring active

- [ ] **Maintenance** (OPERATIONAL-GUIDE.md Section 3)
  - [ ] Weekly maintenance scheduled
  - [ ] Monthly security reviews scheduled
  - [ ] Quarterly audits scheduled

- [ ] **Security Posture**
  - [ ] Credential rotation schedule active
  - [ ] Security patches applied promptly
  - [ ] Threat model reviewed quarterly
  - [ ] Pen testing scheduled annually

### Metrics & KPIs

Track these monthly:

- [ ] **Availability**: CA service uptime %
- [ ] **Performance**: Average certificate issuance time
- [ ] **Quality**: Failed issuance rate
- [ ] **Security**: Security incidents count
- [ ] **Compliance**: Audit findings count

---

## Sign-Off

### Project Team

- [ ] **Project Manager**: __________________ Date: __________
- [ ] **Technical Lead**: __________________ Date: __________
- [ ] **Security Lead**: __________________ Date: __________
- [ ] **Operations Lead**: __________________ Date: __________

### Governance

- [ ] **Change Advisory Board**: __________________ Date: __________
- [ ] **CISO**: __________________ Date: __________
- [ ] **CIO**: __________________ Date: __________

---

## Appendix: Quick Reference

### Critical Success Factors

1. ✅ **Security hardening completed** before production use
2. ✅ **Comprehensive backups** taken before all changes
3. ✅ **Testing in non-prod** environment successful
4. ✅ **Rollback plan** documented and tested
5. ✅ **Communication** with all stakeholders
6. ✅ **Monitoring** in place before go-live
7. ✅ **Legacy CRLs remain online** until all certs expire

### Common Pitfalls to Avoid

- ❌ **Hardcoded credentials** in scripts
- ❌ **Skipping dry-run testing**
- ❌ **Not backing up before registry changes**
- ❌ **Decommissioning legacy CAs too early**
- ❌ **Not keeping legacy CRL distribution points online**
- ❌ **Applying registry patches without review**
- ❌ **Insufficient testing of certificate chains**

### Emergency Contacts

| Scenario | Contact | Phone |
|----------|---------|-------|
| **CA Service Down** | On-Call Engineer | +1-555-0911 |
| **Security Incident** | Security Team | +1-555-0200 |
| **Production Outage** | Incident Manager | +1-555-0999 |

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-18  
**Completion Target**: __________


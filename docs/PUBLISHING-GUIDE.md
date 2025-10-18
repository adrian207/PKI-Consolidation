# PowerShell Gallery Publishing Guide

**Module:** PKI-Consolidation  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**Current Version:** 1.3.0

---

## 📦 Publishing to PowerShell Gallery

This guide covers publishing the PKI-Consolidation module to the PowerShell Gallery.

---

## Prerequisites

### 1. PowerShell Gallery Account
- Create account at https://www.powershellgallery.com
- Generate API key from https://www.powershellgallery.com/account/apikeys
- Store API key securely

### 2. GitHub Secrets Configuration
Add the following secret to your GitHub repository:

```
Name: PSGALLERY_API_KEY
Value: <your-powershell-gallery-api-key>
```

**Settings → Secrets and variables → Actions → New repository secret**

### 3. Local Tools
```powershell
# Install required modules
Install-Module -Name PowerShellGet -Force
Install-Module -Name Pester -MinimumVersion 5.0.0
Install-Module -Name PSScriptAnalyzer
```

---

## 🔄 Version Management

### Semantic Versioning

We follow [Semantic Versioning 2.0.0](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes
- **MINOR** (1.X.0): New features (backwards compatible)
- **PATCH** (1.0.X): Bug fixes

### Updating Version

Use the automated version script:

```powershell
# Bump patch version (1.3.0 → 1.3.1)
.\scripts\Update-ModuleVersion.ps1 -VersionType Patch

# Bump minor version (1.3.0 → 1.4.0)
.\scripts\Update-ModuleVersion.ps1 -VersionType Minor

# Bump major version (1.3.0 → 2.0.0)
.\scripts\Update-ModuleVersion.ps1 -VersionType Major

# Set specific version
.\scripts\Update-ModuleVersion.ps1 -NewVersion '1.4.0'
```

This script automatically:
- ✅ Updates module manifest (.psd1)
- ✅ Updates module file (.psm1)
- ✅ Creates changelog entry
- ✅ Creates git commit
- ✅ Creates git tag

---

## 🚀 Publishing Methods

### Method 1: GitHub Release (Automated) - **Recommended**

1. **Push your changes:**
   ```powershell
   git push origin main
   git push origin v1.4.0  # Push the version tag
   ```

2. **Create GitHub Release:**
   - Go to: https://github.com/adrian207/PKI-Consolidation/releases/new
   - Select tag: `v1.4.0`
   - Title: `PKI-Consolidation v1.4.0`
   - Description: Copy from CHANGELOG.md
   - Click "Publish release"

3. **Automatic Publication:**
   - GitHub Actions workflow triggers automatically
   - Runs all tests
   - Validates module
   - Publishes to PowerShell Gallery
   - Creates release asset (ZIP)

### Method 2: Manual Workflow Trigger

```yaml
# From GitHub Actions tab:
1. Select "Publish to PowerShell Gallery" workflow
2. Click "Run workflow"
3. Enter version: 1.4.0
4. Click "Run workflow"
```

### Method 3: Local Manual Publishing

```powershell
# 1. Test module
cd tests
.\Invoke-AllTests.ps1

# 2. Validate manifest
Test-ModuleManifest .\PKI-Consolidation.psd1

# 3. Publish
$apiKey = Read-Host "Enter PS Gallery API Key" -AsSecureString
$apiKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKey)
)

Publish-Module -Path . -NuGetApiKey $apiKeyPlain -Verbose

# 4. Verify publication
Find-Module PKI-Consolidation
```

---

## ✅ Pre-Publication Checklist

Before publishing, ensure:

- [ ] All tests pass (`.\tests\Invoke-AllTests.ps1`)
- [ ] Version number bumped in manifest and module
- [ ] CHANGELOG.md updated with release notes
- [ ] No sensitive data in code or comments
- [ ] README.md is up to date
- [ ] All documentation is current
- [ ] Git tag created (`v1.4.0`)
- [ ] PSScriptAnalyzer passes (no errors)
- [ ] Module manifest validates (`Test-ModuleManifest`)

---

## 📝 Release Process

### Complete Release Workflow

```powershell
# 1. Create release branch
git checkout -b release/v1.4.0

# 2. Update version
.\scripts\Update-ModuleVersion.ps1 -VersionType Minor

# 3. Update CHANGELOG.md
code .\CHANGELOG.md
# Fill in the new version's Added/Changed/Fixed sections

# 4. Run full test suite
cd tests
.\Invoke-AllTests.ps1 -CodeCoverage

# 5. Validate module
Test-ModuleManifest ..\PKI-Consolidation.psd1
Import-Module ..\PKI-Consolidation.psd1 -Force

# 6. Commit changes (if version script didn't auto-commit)
git add .
git commit -m "chore: Prepare release v1.4.0"

# 7. Merge to main
git checkout main
git merge release/v1.4.0

# 8. Push everything
git push origin main
git push origin v1.4.0

# 9. Create GitHub Release
# Go to GitHub UI and create release from tag

# 10. Verify publication
Start-Sleep -Seconds 300  # Wait 5 minutes
Find-Module PKI-Consolidation -AllVersions
```

---

## 🔍 Post-Publication Verification

### Verify Module is Available

```powershell
# Search for module
Find-Module PKI-Consolidation

# Check all versions
Find-Module PKI-Consolidation -AllVersions

# Install and test
Install-Module PKI-Consolidation -Force
Import-Module PKI-Consolidation
Get-PKIConsolidationVersion
```

### Test Installation

```powershell
# Fresh install in new session
pwsh -NoProfile -Command {
    Install-Module PKI-Consolidation -Force
    Import-Module PKI-Consolidation
    Start-PKIConsolidation -WhatIf
}
```

---

## 🐛 Troubleshooting

### Common Issues

#### "Module already exists"
```powershell
# Update existing module version
Update-ModuleManifest -Path .\PKI-Consolidation.psd1 -ModuleVersion '1.4.1'
```

#### "API Key Invalid"
- Regenerate key at https://www.powershellgallery.com/account/apikeys
- Update GitHub secret

#### "Tests Failed"
```powershell
# Run tests with detailed output
cd tests
Invoke-Pester -Output Detailed
```

#### "Manifest Validation Failed"
```powershell
# Check for syntax errors
Test-ModuleManifest .\PKI-Consolidation.psd1 -Verbose
```

---

## 📊 GitHub Actions Workflows

### Test Workflow (`.github/workflows/test.yml`)

**Triggers:**
- Push to `main` or `develop`
- Pull requests to `main`
- Manual dispatch

**Actions:**
- Runs on Windows Server 2019/2022
- Tests PowerShell 5.1 and 7.3
- Installs Pester and dependencies
- Runs full test suite
- Generates code coverage
- Publishes test results

### Publish Workflow (`.github/workflows/publish.yml`)

**Triggers:**
- GitHub release published
- Manual dispatch (with version input)

**Actions:**
- Validates version numbers
- Runs full test suite
- Validates module manifest
- Publishes to PowerShell Gallery
- Creates release ZIP asset
- Sends success notification

---

## 📈 Version History

| Version | Date | Type | Description |
|---------|------|------|-------------|
| 1.3.0 | 2025-10-18 | Minor | Complete workflow (all 9 phases) |
| 1.2.0 | 2025-10-18 | Minor | Performance & testing |
| 1.1.0 | 2025-10-18 | Minor | Security hardening |
| 1.0.0 | 2025-10-17 | Major | Initial release |

---

## 🔐 Security

### API Key Management

**DO NOT:**
- ❌ Commit API keys to git
- ❌ Share API keys in documentation
- ❌ Use production keys in testing

**DO:**
- ✅ Use GitHub Secrets for CI/CD
- ✅ Rotate keys regularly
- ✅ Use separate keys for testing
- ✅ Revoke compromised keys immediately

### Code Signing (Future)

Consider adding code signing for enhanced trust:
```powershell
# Sign scripts
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
Set-AuthenticodeSignature -FilePath .\PKI-Consolidation.psm1 -Certificate $cert
```

---

## 📞 Support

### Issues with Publishing?

1. **Check workflow logs:** GitHub Actions tab
2. **Verify API key:** PowerShell Gallery account
3. **Test locally:** Manual publish attempt
4. **Open issue:** https://github.com/adrian207/PKI-Consolidation/issues

### PowerShell Gallery Support

- **Help:** https://www.powershellgallery.com/policies/Contact
- **Package Management:** https://docs.microsoft.com/powershell/module/powershellget/

---

## 📚 Additional Resources

- **PowerShell Gallery:** https://www.powershellgallery.com
- **Publishing Modules:** https://docs.microsoft.com/powershell/scripting/gallery/how-to/publishing-packages/publishing-a-package
- **Semantic Versioning:** https://semver.org
- **GitHub Actions:** https://docs.github.com/actions
- **Module Manifests:** https://docs.microsoft.com/powershell/scripting/developer/module/how-to-write-a-powershell-module-manifest

---

**Last Updated:** October 18, 2025  
**Author:** Adrian Johnson <adrian207@gmail.com>  
**License:** MIT


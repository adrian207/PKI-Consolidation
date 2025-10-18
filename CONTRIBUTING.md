# Contributing to PKI-Consolidation Tool

Thank you for your interest in contributing to the PKI-Consolidation Tool! This document provides guidelines for contributing to the project.

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [How to Contribute](#how-to-contribute)
4. [Development Guidelines](#development-guidelines)
5. [Testing Requirements](#testing-requirements)
6. [Documentation Standards](#documentation-standards)
7. [Pull Request Process](#pull-request-process)
8. [Security Vulnerabilities](#security-vulnerabilities)

---

## Code of Conduct

This project adheres to a code of conduct that all contributors are expected to follow:

- **Be respectful**: Treat all community members with respect and kindness
- **Be collaborative**: Work together towards common goals
- **Be professional**: Maintain professionalism in all interactions
- **Be inclusive**: Welcome contributors of all backgrounds and skill levels
- **Be constructive**: Provide helpful feedback and suggestions

Unacceptable behavior includes harassment, trolling, personal attacks, or any conduct that creates an intimidating or hostile environment.

---

## Getting Started

### Prerequisites

- PowerShell 5.1 or later (PowerShell 7+ recommended)
- Active Directory RSAT tools
- AD CS management tools (for testing CA operations)
- Git for version control
- Code editor (VS Code recommended with PowerShell extension)

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```powershell
   git clone https://github.com/YOUR-USERNAME/PKI-Consolidation.git
   cd PKI-Consolidation
   ```
3. Add upstream remote:
   ```powershell
   git remote add upstream https://github.com/ORIGINAL-OWNER/PKI-Consolidation.git
   ```

### Development Setup

```powershell
# Install required modules
Install-Module -Name PSPKI -Force
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name Pester -Force

# Verify installation
Get-Module -ListAvailable PSPKI, PSScriptAnalyzer, Pester
```

---

## How to Contribute

### Reporting Bugs

**Before submitting a bug report:**
- Check existing issues to avoid duplicates
- Verify the bug exists in the latest version
- Test in a clean environment if possible

**Bug Report Template:**
```markdown
## Bug Description
[Clear description of the bug]

## Steps to Reproduce
1. Step one
2. Step two
3. ...

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Environment
- Windows Version: [e.g., Server 2022]
- PowerShell Version: [e.g., 7.4.0]
- Script Version: [e.g., 1.0]
- Domain Functional Level: [e.g., 2016]

## Logs/Screenshots
[Attach relevant logs or screenshots]

## Additional Context
[Any other relevant information]
```

### Suggesting Enhancements

**Enhancement Request Template:**
```markdown
## Feature Description
[Clear description of the proposed feature]

## Use Case
[Why is this feature needed?]

## Proposed Solution
[How should it work?]

## Alternatives Considered
[What other approaches did you consider?]

## Additional Context
[Any other relevant information]
```

### Contributing Code

1. **Create a branch** for your feature or fix:
   ```powershell
   git checkout -b feature/your-feature-name
   # or
   git checkout -b bugfix/issue-123
   ```

2. **Make your changes** following the development guidelines

3. **Test thoroughly** (see Testing Requirements)

4. **Commit with clear messages**:
   ```powershell
   git commit -m "Add feature: Description of changes
   
   - Detailed point 1
   - Detailed point 2
   
   Fixes #123"
   ```

5. **Push to your fork**:
   ```powershell
   git push origin feature/your-feature-name
   ```

6. **Open a Pull Request** against the main branch

---

## Development Guidelines

### PowerShell Style Guide

**General Principles:**
- Follow PowerShell best practices and conventions
- Use approved verbs (`Get-Verb` for list)
- Write self-documenting code with clear names
- Add comments for complex logic

**Naming Conventions:**
```powershell
# Functions: Verb-Noun pattern with PascalCase
function Get-CAConfiguration { }

# Variables: camelCase for local, PascalCase with $Global: prefix for global
$localVariable = "value"
$Global:ConfigurationPath = "path"

# Parameters: PascalCase
param([string]$ParameterName)

# Constants: UPPER_SNAKE_CASE (conventionally)
$MAX_RETRY_COUNT = 3
```

**Code Structure:**
```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
    Brief description
    
    .DESCRIPTION
    Detailed description
    
    .PARAMETER ParamName
    Parameter description
    
    .EXAMPLE
    Verb-Noun -ParamName "value"
    Description of example
    
    .NOTES
    Additional notes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ParamName
    )
    
    begin {
        Write-Verbose "Starting Verb-Noun"
    }
    
    process {
        try {
            # Main logic here
        }
        catch {
            Write-Error "Error in Verb-Noun: $($_.Exception.Message)"
            throw
        }
    }
    
    end {
        Write-Verbose "Completed Verb-Noun"
    }
}
```

### Error Handling

**Always use try-catch for external operations:**
```powershell
try {
    $result = Invoke-ExternalCommand -Parameter $value
    Write-Log "Operation successful: $result"
}
catch {
    Write-Log "Operation failed: $($_.Exception.Message)" 'ERROR'
    throw
}
```

### Logging

**Use the centralized Write-Log function:**
```powershell
Write-Log "Informational message" 'INFO'
Write-Log "Warning message" 'WARN'
Write-Log "Error message" 'ERROR'
```

### Security Considerations

**Critical rules:**
- NEVER commit credentials, API keys, or certificates
- Always validate and sanitize user input
- Use parameterized queries and proper escaping
- Follow principle of least privilege
- Log security-relevant events

**Example - Input Validation:**
```powershell
function Test-SafePath {
    param([string]$Path)
    
    # Block path traversal
    if ($Path -match '\.\.') {
        throw "Invalid path: path traversal detected"
    }
    
    # Normalize and validate
    $normalized = [System.IO.Path]::GetFullPath($Path)
    return $normalized
}

# Use in code
$safePath = Test-SafePath -Path $userInput
```

---

## Testing Requirements

### Static Analysis

**Run PSScriptAnalyzer before committing:**
```powershell
Invoke-ScriptAnalyzer -Path .\PKI-Consolidation.ps1 -Severity Error,Warning
```

**Fix all critical and error-level findings. Warnings should be addressed or documented.**

### Manual Testing

**Test checklist:**
- [ ] Dry-run mode works correctly (no actual changes)
- [ ] Error handling works as expected
- [ ] Logging captures all operations
- [ ] No sensitive data in logs
- [ ] Rollback procedures work
- [ ] Help documentation is accurate

### Test in Lab Environment

**Before submitting PRs that modify core functionality:**
1. Set up test AD CS environment
2. Run full consolidation workflow
3. Verify no errors in logs
4. Test rollback procedures
5. Document test results in PR

### Unit Tests (Future)

We're working on adding Pester-based unit tests. Example:

```powershell
Describe "Get-CARegistryKeys" {
    Context "When CA service is installed" {
        It "Returns CA configuration objects" {
            $result = Get-CARegistryKeys
            $result | Should -Not -BeNullOrEmpty
            $result[0].CAName | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "When no CA service exists" {
        Mock Get-ChildItem { return @() }
        
        It "Returns empty array" {
            $result = Get-CARegistryKeys
            $result | Should -BeNullOrEmpty
        }
    }
}
```

---

## Documentation Standards

### Code Documentation

**Every function must have comment-based help:**
```powershell
<#
.SYNOPSIS
Brief one-line description

.DESCRIPTION
Detailed description of what the function does, how it works,
and any important considerations

.PARAMETER ParameterName
Description of the parameter

.EXAMPLE
Example-Function -ParameterName "value"
Description of what this example does

.NOTES
Author: Your Name
Version: 1.0
#>
```

### Markdown Documentation

**Update relevant documentation when making changes:**
- README.md for user-facing changes
- DESIGN-DOCUMENT.md for architecture changes
- DEPLOYMENT-GUIDE.md for deployment process changes
- SECURITY-HARDENING.md for security-related changes
- OPERATIONAL-GUIDE.md for operational procedure changes

**Documentation style:**
- Use clear, concise language
- Include code examples where applicable
- Add diagrams for complex concepts
- Keep table of contents updated
- Use proper markdown formatting

---

## Pull Request Process

### Before Submitting

- [ ] Code follows style guidelines
- [ ] All tests pass
- [ ] PSScriptAnalyzer shows no critical issues
- [ ] Documentation updated
- [ ] Commit messages are clear and descriptive
- [ ] No merge conflicts with main branch

### PR Template

```markdown
## Description
[Clear description of changes]

## Type of Change
- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature causing existing functionality to change)
- [ ] Documentation update
- [ ] Security enhancement

## Related Issues
Fixes #[issue number]
Related to #[issue number]

## Testing Performed
- [ ] Dry-run mode tested
- [ ] Lab environment testing completed
- [ ] PSScriptAnalyzer clean
- [ ] Manual testing checklist completed

## Test Results
[Describe test results or attach logs]

## Screenshots (if applicable)
[Add screenshots]

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings introduced
- [ ] Tested in clean environment
```

### Review Process

1. **Automated checks** run on PR submission
2. **Maintainer review** within 5 business days
3. **Address feedback** and push updates
4. **Final approval** requires 2 maintainer approvals for core changes
5. **Merge** by maintainer once approved

### After Merge

- Your branch will be deleted automatically
- Update your fork:
  ```powershell
  git checkout main
  git pull upstream main
  git push origin main
  ```

---

## Security Vulnerabilities

**DO NOT** open public issues for security vulnerabilities.

**Instead:**
1. Email security details to: **adrian207@gmail.com** with subject: "[SECURITY] PKI-Consolidation"
2. Include:
   - Description of vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
3. Allow 90 days for fix before public disclosure
4. We'll acknowledge within 48 hours
5. Credit will be given in security advisory (if desired)

---

## Recognition

Contributors will be recognized in:
- CONTRIBUTORS.md file
- Release notes
- GitHub contributor graph

Significant contributions may result in:
- Maintainer status
- Direct commit access
- Project decision-making participation

---

## Questions?

- **General questions:** Open a discussion on GitHub
- **Bug reports:** Open an issue using bug template
- **Feature requests:** Open an issue using enhancement template
- **Security issues:** Email Adrian Johnson at adrian207@gmail.com
- **Project inquiries:** adrian207@gmail.com

---

## License

By contributing to this project, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for contributing to PKI-Consolidation Tool!** 🚀

Every contribution, no matter how small, helps make enterprise PKI consolidation safer and more efficient for everyone.


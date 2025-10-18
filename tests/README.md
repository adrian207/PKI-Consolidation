# PKI-Consolidation Test Suite

Comprehensive Pester-based test suite for the PKI-Consolidation tool.

**Author:** Adrian Johnson <adrian207@gmail.com>

## Overview

This directory contains unit and integration tests for all PKI-Consolidation modules using Pester 5.0+.

## Prerequisites

- **PowerShell 5.1+** (PowerShell 7+ recommended for best performance)
- **Pester 5.0+** - Test framework

### Installing Pester

```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force
```

## Test Files

| Test File | Module Under Test | Description |
|-----------|-------------------|-------------|
| `PKI-Security.Tests.ps1` | `PKI-Security.psm1` | Input validation, secure logging, file permissions, privilege checks |
| `PKI-Performance.Tests.ps1` | `PKI-Performance.psm1` | Certificate store caching, parallel processing, performance monitoring |
| `PKI-OCSP.Tests.ps1` | `PKI-OCSP.psm1` | OCSP responder testing, certificate validation, health checks |

## Running Tests

### Run All Tests

```powershell
# Simple console output
.\Invoke-AllTests.ps1

# With detailed output
.\Invoke-AllTests.ps1 -OutputFormat Console -Verbose

# Generate NUnit XML report
.\Invoke-AllTests.ps1 -OutputFormat NUnitXml

# With code coverage analysis
.\Invoke-AllTests.ps1 -CodeCoverage
```

### Run Individual Test Files

```powershell
# Run security tests only
Invoke-Pester -Path .\PKI-Security.Tests.ps1

# Run with detailed output
Invoke-Pester -Path .\PKI-Performance.Tests.ps1 -Output Detailed

# Run specific test
Invoke-Pester -Path .\PKI-OCSP.Tests.ps1 -FullNameFilter '*Test-OCSPResponder*'
```

### Run Specific Test Categories

```powershell
# Run all input validation tests
Invoke-Pester -Path .\PKI-Security.Tests.ps1 -TagFilter 'InputValidation'

# Run all integration tests
Invoke-Pester -Path . -TagFilter 'Integration'
```

## Test Output

Test results are saved to the `test-results/` directory (automatically created).

### Output Formats

- **Console** - Human-readable output in terminal
- **NUnitXml** - XML format compatible with CI/CD systems (Azure DevOps, Jenkins)
- **JUnitXml** - XML format compatible with JUnit parsers

### Code Coverage

When running with `-CodeCoverage`, reports are generated in JaCoCo XML format:

```
test-results/
  ├── test-results-20251018-143022.xml
  └── coverage-20251018-143022.xml
```

Coverage reports can be visualized using tools like:
- **ReportGenerator**
- **Codecov**
- **SonarQube**

## Test Structure

Tests follow Pester 5.0+ syntax with the following structure:

```powershell
BeforeAll {
    # Module imports and setup
}

Describe 'Feature Area' {
    Context 'Specific Functionality' {
        It 'Should do something specific' {
            # Arrange
            $input = 'test'
            
            # Act
            $result = Invoke-Function -Input $input
            
            # Assert
            $result | Should -Be 'expected'
        }
    }
}

AfterAll {
    # Cleanup
}
```

## Writing New Tests

### Best Practices

1. **Arrange-Act-Assert Pattern**
   ```powershell
   It 'Should validate input' {
       # Arrange
       $invalidInput = '../../../etc/passwd'
       
       # Act & Assert
       { Test-SafePath -Path $invalidInput } | Should -Throw
   }
   ```

2. **Use TestDrive for File Operations**
   ```powershell
   It 'Should create log file' {
       $logPath = Join-Path $TestDrive 'test.log'
       Write-SecureLog -Message 'Test' -LogPath $logPath
       Test-Path $logPath | Should -Be $true
   }
   ```

3. **Skip Environment-Specific Tests**
   ```powershell
   It 'Should test Windows-only feature' -Skip:(-not $IsWindows) {
       # Windows-specific test
   }
   ```

4. **Mock External Dependencies**
   ```powershell
   BeforeAll {
       Mock Invoke-WebRequest { return @{ StatusCode = 200 } }
   }
   ```

### Test Naming Conventions

- **Describe** - Module or feature area
- **Context** - Specific functionality group
- **It** - Individual test case (should be descriptive and start with "Should")

### Test Categories (Tags)

Use tags to organize tests:

```powershell
It 'Should validate paths' -Tag 'InputValidation', 'Security' {
    # Test code
}
```

Run tagged tests:
```powershell
Invoke-Pester -TagFilter 'Security'
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Pester
        shell: pwsh
        run: Install-Module -Name Pester -MinimumVersion 5.0.0 -Force
      
      - name: Run Tests
        shell: pwsh
        run: |
          cd tests
          .\Invoke-AllTests.ps1 -OutputFormat NUnitXml -CodeCoverage
      
      - name: Publish Test Results
        uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: tests/test-results/*.xml
```

### Azure DevOps Pipeline Example

```yaml
trigger:
  - main

pool:
  vmImage: 'windows-latest'

steps:
- task: PowerShell@2
  displayName: 'Install Pester'
  inputs:
    targetType: 'inline'
    script: 'Install-Module -Name Pester -MinimumVersion 5.0.0 -Force'

- task: PowerShell@2
  displayName: 'Run Tests'
  inputs:
    filePath: 'tests/Invoke-AllTests.ps1'
    arguments: '-OutputFormat NUnitXml -CodeCoverage'

- task: PublishTestResults@2
  displayName: 'Publish Test Results'
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: '**/test-results/*.xml'
```

## Troubleshooting

### Pester Version Conflicts

If you have multiple Pester versions installed:

```powershell
# Remove old versions
Get-Module Pester -ListAvailable | Where-Object Version -lt 5.0.0 | Uninstall-Module -Force

# Import specific version
Import-Module Pester -MinimumVersion 5.0.0 -Force
```

### Module Not Found Errors

Ensure modules are in the correct location:

```
PKI-Consolidation/
  ├── modules/
  │   ├── PKI-Security.psm1
  │   ├── PKI-Performance.psm1
  │   └── PKI-OCSP.psm1
  └── tests/
      ├── PKI-Security.Tests.ps1
      ├── PKI-Performance.Tests.ps1
      └── PKI-OCSP.Tests.ps1
```

### Permission Errors

Some tests require elevated privileges:

```powershell
# Run as Administrator
Start-Process pwsh -Verb RunAs -ArgumentList "-NoExit -Command cd '$PWD'; .\Invoke-AllTests.ps1"
```

## Code Coverage Goals

| Module | Target Coverage | Current Status |
|--------|----------------|----------------|
| PKI-Security | 85% | [Unverified] |
| PKI-Performance | 80% | [Unverified] |
| PKI-OCSP | 75% | [Unverified] |

## Contributing

When adding new features:

1. Write tests first (TDD approach recommended)
2. Ensure all tests pass before committing
3. Aim for >80% code coverage on new code
4. Update this README if adding new test files

## Support

For issues or questions:
- **Email:** adrian207@gmail.com
- **GitHub Issues:** https://github.com/adrian207/PKI-Consolidation/issues

## License

Copyright (c) 2025 Adrian Johnson <adrian207@gmail.com>

Licensed under the MIT License. See LICENSE file for details.


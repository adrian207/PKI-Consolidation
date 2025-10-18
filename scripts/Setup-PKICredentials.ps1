#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-time setup script for PKI-Consolidation Tool credentials

.DESCRIPTION
    Configures secure credential storage for API keys and sensitive configuration.
    Must be run once before using the PKI-Consolidation Tool in production.

.PARAMETER KeyfactorAPIKey
    The Keyfactor API key (will be prompted securely if not provided)

.PARAMETER AzureKeyVaultName
    The Azure Key Vault name (optional)

.PARAMETER GenerateLogHMACKey
    Generates and stores an HMAC key for log integrity protection

.EXAMPLE
    .\Setup-PKICredentials.ps1 -GenerateLogHMACKey

.AUTHOR
    Adrian Johnson <adrian207@gmail.com>

.LINK
    https://github.com/adrian207/PKI-Consolidation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [System.Security.SecureString]$KeyfactorAPIKey,
    
    [Parameter(Mandatory = $false)]
    [string]$AzureKeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [switch]$GenerateLogHMACKey
)

$ErrorActionPreference = 'Stop'

# Banner
Write-Host @"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║        PKI-Consolidation Tool - Credential Setup            ║
║                                                               ║
║        Author: Adrian Johnson <adrian207@gmail.com>          ║
║        Version: 1.1.0                                         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Import security module
$modulePath = Join-Path $PSScriptRoot "..\modules\PKI-Security.psm1"
if (-not (Test-Path $modulePath)) {
    Write-Error "Security module not found: $modulePath"
    exit 1
}

Write-Host "[1/5] Importing security module..." -ForegroundColor Yellow
Import-Module $modulePath -Force

# Validate privileges
Write-Host "`n[2/5] Validating privileges..." -ForegroundColor Yellow
try {
    Test-RequiredPrivileges -ThrowOnFailure -Verbose
    Write-Host "✓ Privilege validation passed`n" -ForegroundColor Green
}
catch {
    Write-Host "✗ Privilege validation failed: $($_.Exception.Message)`n" -ForegroundColor Red
    exit 1
}

# Install CredentialManager module if needed
Write-Host "[3/5] Checking CredentialManager module..." -ForegroundColor Yellow
if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
    Write-Host "  Installing CredentialManager module..." -ForegroundColor Cyan
    try {
        Install-Module -Name CredentialManager -Force -Scope CurrentUser
        Write-Host "✓ CredentialManager module installed`n" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed to install CredentialManager: $($_.Exception.Message)`n" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "✓ CredentialManager module already installed`n" -ForegroundColor Green
}

# Configure credentials
Write-Host "[4/5] Configuring credentials..." -ForegroundColor Yellow

# Keyfactor API Key
if (-not $KeyfactorAPIKey) {
    $response = Read-Host "Do you want to configure Keyfactor API key? (Y/N)"
    if ($response -eq 'Y') {
        $KeyfactorAPIKey = Read-Host -Prompt "Enter Keyfactor API Key" -AsSecureString
    }
}

if ($KeyfactorAPIKey) {
    try {
        Set-PKICredential -Target "KeyfactorAPIKey" -Password $KeyfactorAPIKey -Verbose
        Write-Host "✓ Keyfactor API key stored securely" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed to store Keyfactor API key: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Azure Key Vault
if ($AzureKeyVaultName) {
    Write-Host "`n  Testing Azure Key Vault connection..." -ForegroundColor Cyan
    try {
        # Test Azure CLI authentication
        $null = & az account show 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Azure CLI authenticated" -ForegroundColor Green
            Write-Host "  Vault Name: $AzureKeyVaultName" -ForegroundColor Cyan
        }
        else {
            Write-Host "✗ Azure CLI not authenticated. Run 'az login' first." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ Azure CLI not installed or not in PATH" -ForegroundColor Red
    }
}

# Generate Log HMAC Key
if ($GenerateLogHMACKey) {
    Write-Host "`n  Generating HMAC key for log integrity..." -ForegroundColor Cyan
    try {
        # Generate 256-bit random key
        $hmacKeyBytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
        $rng.GetBytes($hmacKeyBytes)
        $hmacKeyString = [Convert]::ToBase64String($hmacKeyBytes)
        $hmacKeySecure = ConvertTo-SecureString $hmacKeyString -AsPlainText -Force
        
        Set-PKICredential -Target "LogHMACKey" -Password $hmacKeySecure -Verbose
        Write-Host "✓ Log HMAC key generated and stored securely" -ForegroundColor Green
        
        # Clear sensitive data
        $hmacKeyString = $null
        $hmacKeyBytes = $null
        [System.GC]::Collect()
    }
    catch {
        Write-Host "✗ Failed to generate HMAC key: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n[5/5] Setup Summary" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$storedCreds = @()
try {
    $kfCred = Get-PKICredential -Target "KeyfactorAPIKey" -ErrorAction SilentlyContinue
    if ($kfCred) { $storedCreds += "Keyfactor API Key" }
}
catch { }

try {
    $hmacCred = Get-PKICredential -Target "LogHMACKey" -ErrorAction SilentlyContinue
    if ($hmacCred) { $storedCreds += "Log HMAC Key" }
}
catch { }

if ($storedCreds.Count -gt 0) {
    Write-Host "`n✓ Credentials stored:" -ForegroundColor Green
    $storedCreds | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
}
else {
    Write-Host "`n⚠ No credentials configured" -ForegroundColor Yellow
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Next steps
Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Review and update PKI-Consolidation.ps1 configuration" -ForegroundColor White
Write-Host "  2. Edit config/crl-aia-ocsp.json with your CA settings" -ForegroundColor White
Write-Host "  3. Run Test-PKIReadiness.ps1 to validate environment" -ForegroundColor White
Write-Host "  4. Execute PKI-Consolidation.ps1 in dry-run mode first" -ForegroundColor White

Write-Host "`n✓ Setup complete!`n" -ForegroundColor Green


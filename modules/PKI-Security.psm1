#Requires -Version 5.1
<#
.SYNOPSIS
    Security module for PKI-Consolidation Tool

.DESCRIPTION
    Provides secure credential management, privilege validation, file permissions,
    and audit trail protection for the PKI-Consolidation Tool.

.AUTHOR
    Adrian Johnson <adrian207@gmail.com>

.VERSION
    1.1.0

.LINK
    https://github.com/adrian207/PKI-Consolidation
#>

#region Credential Management

<#
.SYNOPSIS
    Stores a credential securely in Windows Credential Manager

.PARAMETER Target
    The target name for the credential (e.g., "KeyfactorAPIKey")

.PARAMETER Username
    The username (default: "PKI-Tool")

.PARAMETER Password
    The secure string password to store

.EXAMPLE
    $apiKey = Read-Host -Prompt "Enter API Key" -AsSecureString
    Set-PKICredential -Target "KeyfactorAPIKey" -Password $apiKey
#>
function Set-PKICredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,
        
        [Parameter(Mandatory = $false)]
        [string]$Username = 'PKI-Tool',
        
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Password
    )
    
    begin {
        Write-Verbose "Setting credential for target: $Target"
        
        # Ensure CredentialManager module is available
        if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
            Write-Warning "CredentialManager module not found. Installing..."
            try {
                Install-Module -Name CredentialManager -Force -Scope CurrentUser -ErrorAction Stop
                Write-Verbose "CredentialManager module installed successfully"
            }
            catch {
                throw "Failed to install CredentialManager module: $($_.Exception.Message)"
            }
        }
        
        Import-Module CredentialManager -ErrorAction Stop
    }
    
    process {
        try {
            $credPath = "PKI-Consolidation:$Target"
            
            # Convert SecureString to plain text for storage
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            
            # Remove existing credential if present
            $existing = Get-StoredCredential -Target $credPath -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-StoredCredential -Target $credPath -ErrorAction SilentlyContinue
                Write-Verbose "Removed existing credential"
            }
            
            # Store new credential
            New-StoredCredential -Target $credPath -UserName $Username -Password $plainPassword -Persist LocalMachine | Out-Null
            
            Write-Verbose "Credential stored successfully: $credPath"
            return $true
        }
        catch {
            Write-Error "Failed to store credential: $($_.Exception.Message)"
            throw
        }
        finally {
            # Clear sensitive data from memory
            if ($plainPassword) {
                $plainPassword = $null
                [System.GC]::Collect()
            }
        }
    }
}

<#
.SYNOPSIS
    Retrieves a credential from Windows Credential Manager

.PARAMETER Target
    The target name for the credential

.EXAMPLE
    $cred = Get-PKICredential -Target "KeyfactorAPIKey"
    $apiKey = $cred.GetNetworkCredential().Password
#>
function Get-PKICredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target
    )
    
    begin {
        if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
            throw "CredentialManager module not installed. Run Set-PKICredential first or Install-Module CredentialManager."
        }
        Import-Module CredentialManager -ErrorAction Stop
    }
    
    process {
        try {
            $credPath = "PKI-Consolidation:$Target"
            $cred = Get-StoredCredential -Target $credPath -ErrorAction Stop
            
            if (-not $cred) {
                throw "Credential not found: $credPath. Run Set-PKICredential to store it first."
            }
            
            Write-Verbose "Retrieved credential: $credPath"
            return $cred
        }
        catch {
            Write-Error "Failed to retrieve credential '$Target': $($_.Exception.Message)"
            throw
        }
    }
}

<#
.SYNOPSIS
    Retrieves a secret from Azure Key Vault

.PARAMETER VaultName
    The name of the Azure Key Vault

.PARAMETER SecretName
    The name of the secret to retrieve

.EXAMPLE
    $apiKey = Get-AzureKeyVaultSecret -VaultName "contoso-pki-vault" -SecretName "KeyfactorAPIKey"
#>
function Get-AzureKeyVaultSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName
    )
    
    begin {
        Write-Verbose "Retrieving secret '$SecretName' from Azure Key Vault '$VaultName'"
    }
    
    process {
        try {
            # Check if Azure CLI is authenticated
            $accountCheck = & az account show 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Azure CLI not authenticated. Run 'az login' first."
            }
            
            # Retrieve secret
            $secret = & az keyvault secret show --vault-name $VaultName --name $SecretName --query value -o tsv 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to retrieve secret: $secret"
            }
            
            Write-Verbose "Secret retrieved successfully"
            return $secret
        }
        catch {
            Write-Error "Failed to retrieve Azure Key Vault secret: $($_.Exception.Message)"
            throw
        }
    }
}

#endregion

#region Privilege Validation

<#
.SYNOPSIS
    Validates that the script is running with required privileges

.DESCRIPTION
    Checks for Local Administrator, Enterprise Admin, and CA Administrator permissions

.PARAMETER ThrowOnFailure
    If $true, throws an exception if required privileges are missing. If $false, returns validation result.

.EXAMPLE
    Test-RequiredPrivileges -ThrowOnFailure
#>
function Test-RequiredPrivileges {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnFailure
    )
    
    begin {
        Write-Verbose "Validating execution privileges..."
        $results = @()
    }
    
    process {
        # Test 1: Local Administrator
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        $results += [PSCustomObject]@{
            Check    = 'Local Administrator'
            Status   = if ($isAdmin) { 'PASS' } else { 'FAIL' }
            Required = $true
            Message  = if ($isAdmin) { 'Confirmed' } else { 'This script requires local administrator privileges' }
        }
        
        if (-not $isAdmin -and $ThrowOnFailure) {
            throw "This script requires local administrator privileges. Please run as administrator."
        }
        
        # Test 2: Enterprise Admin (for AD operations)
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            $configNC = (Get-ADRootDSE).ConfigurationNamingContext
            $domain = $configNC -replace '^.*?DC=', '' -replace ',DC=', '.'
            $enterpriseAdmins = Get-ADGroup "Enterprise Admins" -Server $domain -ErrorAction Stop
            $isMember = (Get-ADGroupMember $enterpriseAdmins -Recursive -ErrorAction Stop | 
                Where-Object { $_.SID -eq $identity.User }) -ne $null
            
            $results += [PSCustomObject]@{
                Check    = 'Enterprise Admin'
                Status   = if ($isMember) { 'PASS' } else { 'WARN' }
                Required = $false
                Message  = if ($isMember) { 'Confirmed' } else { 'Not an Enterprise Admin. AD publication operations may fail.' }
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Check    = 'Enterprise Admin'
                Status   = 'ERROR'
                Required = $false
                Message  = "Could not verify: $($_.Exception.Message)"
            }
        }
        
        # Test 3: CA Administrator (if CertSvc exists)
        $certSvc = Get-Service CertSvc -ErrorAction SilentlyContinue
        if ($certSvc) {
            try {
                $ping = & certutil -ping 2>&1
                $caAdmin = $LASTEXITCODE -eq 0
                
                $results += [PSCustomObject]@{
                    Check    = 'CA Administrator'
                    Status   = if ($caAdmin) { 'PASS' } else { 'WARN' }
                    Required = $false
                    Message  = if ($caAdmin) { 'Confirmed (certutil -ping succeeded)' } else { 'CA service not responding or insufficient permissions' }
                }
            }
            catch {
                $results += [PSCustomObject]@{
                    Check    = 'CA Administrator'
                    Status   = 'WARN'
                    Required = $false
                    Message  = "Could not verify: $($_.Exception.Message)"
                }
            }
        }
        
        # Test 4: Registry write access
        $testKey = "HKLM:\SOFTWARE\PKI-Consolidation-Test-$(Get-Random)"
        try {
            New-Item -Path $testKey -Force -ErrorAction Stop | Out-Null
            Remove-Item -Path $testKey -Force -ErrorAction Stop
            
            $results += [PSCustomObject]@{
                Check    = 'Registry Write Access'
                Status   = 'PASS'
                Required = $true
                Message  = 'Confirmed'
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Check    = 'Registry Write Access'
                Status   = 'FAIL'
                Required = $true
                Message  = 'Registry write access denied. Cannot proceed.'
            }
            
            if ($ThrowOnFailure) {
                throw "Registry write access denied. Cannot proceed."
            }
        }
        
        # Display results
        $results | Format-Table -AutoSize
        
        # Check for failures
        $failures = $results | Where-Object { $_.Status -eq 'FAIL' }
        if ($failures -and $ThrowOnFailure) {
            throw "Missing required permissions. Please run as an Enterprise Admin with local administrator privileges."
        }
        
        Write-Verbose "Privilege validation complete."
        return [PSCustomObject]@{
            HasRequiredPrivileges = ($failures.Count -eq 0)
            Results               = $results
        }
    }
}

#endregion

#region File System Security

<#
.SYNOPSIS
    Hardens permissions on a directory to SYSTEM + Administrators only

.PARAMETER Path
    The directory path to secure

.EXAMPLE
    Set-SecureDirectoryPermissions -Path "C:\PKI\Consolidation\config"
#>
function Set-SecureDirectoryPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Path
    )
    
    begin {
        Write-Verbose "Hardening permissions on: $Path"
    }
    
    process {
        try {
            # Get current ACL
            $acl = Get-Acl $Path
            
            # Disable inheritance
            $acl.SetAccessRuleProtection($true, $false)
            
            # Remove all existing rules
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
            
            # Grant SYSTEM full control
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'NT AUTHORITY\SYSTEM',
                'FullControl',
                'ContainerInherit,ObjectInherit',
                'None',
                'Allow'
            )
            $acl.SetAccessRule($systemRule)
            
            # Grant Administrators full control
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'BUILTIN\Administrators',
                'FullControl',
                'ContainerInherit,ObjectInherit',
                'None',
                'Allow'
            )
            $acl.SetAccessRule($adminRule)
            
            # Apply ACL
            Set-Acl -Path $Path -AclObject $acl
            
            Write-Verbose "Permissions hardened successfully: $Path (SYSTEM + Administrators only)"
            return $true
        }
        catch {
            Write-Error "Failed to harden permissions on '$Path': $($_.Exception.Message)"
            throw
        }
    }
}

<#
.SYNOPSIS
    Secures a log file with read-only permissions for Administrators

.PARAMETER FilePath
    The log file path to secure

.EXAMPLE
    Set-SecureLogFilePermissions -FilePath "C:\PKI\Consolidation\PKI-Consolidation.log"
#>
function Set-SecureLogFilePermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$FilePath
    )
    
    begin {
        Write-Verbose "Securing log file: $FilePath"
    }
    
    process {
        try {
            $acl = Get-Acl $FilePath
            $acl.SetAccessRuleProtection($true, $false)
            
            # SYSTEM: Full Control
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'NT AUTHORITY\SYSTEM', 'FullControl', 'Allow'
            )
            $acl.SetAccessRule($systemRule)
            
            # Administrators: Read + Append
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'BUILTIN\Administrators', 'Read,AppendData', 'Allow'
            )
            $acl.SetAccessRule($adminRule)
            
            Set-Acl -Path $FilePath -AclObject $acl
            
            Write-Verbose "Log file permissions secured (SYSTEM: Full, Admins: Read+Append)"
            return $true
        }
        catch {
            Write-Error "Failed to secure log file '$FilePath': $($_.Exception.Message)"
            throw
        }
    }
}

#endregion

#region Audit Trail Protection

<#
.SYNOPSIS
    Writes a log entry with HMAC integrity protection

.PARAMETER Message
    The log message

.PARAMETER Level
    The log level (INFO, WARN, ERROR, DEBUG)

.PARAMETER SessionID
    The session identifier

.PARAMETER Component
    The component generating the log entry

.PARAMETER LogPath
    The path to the log file

.PARAMETER HMACKey
    The HMAC key for integrity protection (SecureString)

.EXAMPLE
    Write-SecureLog -Message "Operation completed" -Level "INFO" -LogPath "C:\PKI\Consolidation\PKI-Consolidation.log" -HMACKey $hmacKey
#>
function Write-SecureLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',
        
        [Parameter(Mandatory = $false)]
        [string]$SessionID = [Guid]::NewGuid().ToString(),
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'Main',
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [System.Security.SecureString]$HMACKey
    )
    
    begin {
        $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'
        $computerName = $env:COMPUTERNAME
        $user = $env:USERNAME
    }
    
    process {
        try {
            # Structured log entry (JSON)
            $logEntry = @{
                Timestamp   = $timestamp
                Level       = $Level
                SessionID   = $SessionID
                User        = $user
                Computer    = $computerName
                Component   = $Component
                Message     = $Message
                ProcessID   = $PID
            }
            
            $logLine = $logEntry | ConvertTo-Json -Compress
            
            # Calculate HMAC if key provided
            if ($HMACKey) {
                try {
                    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($HMACKey)
                    $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                    
                    $hmac = New-Object System.Security.Cryptography.HMACSHA256
                    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($plainKey)
                    $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($logLine))
                    $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''
                    $logLine = "$logLine|HMAC:$hashString"
                    
                    # Clear sensitive data
                    $plainKey = $null
                    [System.GC]::Collect()
                }
                catch {
                    Write-Warning "HMAC calculation failed: $($_.Exception.Message)"
                }
            }
            
            # Console output (structured for readability)
            $color = switch ($Level) {
                'ERROR' { 'Red' }
                'WARN' { 'Yellow' }
                'DEBUG' { 'Gray' }
                default { 'White' }
            }
            Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
            
            # File output
            Add-Content -Path $LogPath -Value $logLine -ErrorAction Stop
            
            # Event log output for critical events
            if ($Level -eq 'ERROR') {
                try {
                    # Create event source if it doesn't exist
                    if (-not ([System.Diagnostics.EventLog]::SourceExists('PKI-Consolidation'))) {
                        New-EventLog -LogName Application -Source 'PKI-Consolidation' -ErrorAction SilentlyContinue
                    }
                    Write-EventLog -LogName Application -Source 'PKI-Consolidation' -EventId 1001 -EntryType Error -Message $Message -ErrorAction SilentlyContinue
                }
                catch {
                    # Silently fail if event log write fails
                }
            }
            
            return $true
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
            return $false
        }
    }
}

<#
.SYNOPSIS
    Verifies the integrity of a log file using HMAC

.PARAMETER LogPath
    The path to the log file

.PARAMETER HMACKey
    The HMAC key used to sign the log entries

.EXAMPLE
    Test-LogIntegrity -LogPath "C:\PKI\Consolidation\PKI-Consolidation.log" -HMACKey $hmacKey
#>
function Test-LogIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ })]
        [string]$LogPath,
        
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$HMACKey
    )
    
    begin {
        Write-Verbose "Verifying log integrity: $LogPath"
    }
    
    process {
        try {
            # Get HMAC key
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($HMACKey)
            $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            
            $hmac = New-Object System.Security.Cryptography.HMACSHA256
            $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($plainKey)
            
            # Clear sensitive data
            $plainKey = $null
            [System.GC]::Collect()
            
            # Read log file
            $lines = Get-Content $LogPath
            $tamperedCount = 0
            $totalCount = 0
            
            foreach ($line in $lines) {
                if ($line -match '(.*)\|HMAC:(.+)$') {
                    $totalCount++
                    $content = $Matches[1]
                    $storedHash = $Matches[2]
                    
                    $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($content))
                    $computedHash = [BitConverter]::ToString($hashBytes) -replace '-', ''
                    
                    if ($computedHash -ne $storedHash) {
                        Write-Warning "Tampered entry detected: $($content.Substring(0, [Math]::Min(100, $content.Length)))..."
                        $tamperedCount++
                    }
                }
            }
            
            $result = [PSCustomObject]@{
                TotalEntries    = $totalCount
                TamperedEntries = $tamperedCount
                IsValid         = ($tamperedCount -eq 0)
                IntegrityScore  = if ($totalCount -gt 0) { (($totalCount - $tamperedCount) / $totalCount) * 100 } else { 0 }
            }
            
            if ($result.IsValid) {
                Write-Host "[OK] Log integrity verified. No tampering detected." -ForegroundColor Green
            }
            else {
                Write-Host "[ERROR] $tamperedCount of $totalCount log entries have been tampered with!" -ForegroundColor Red
            }
            
            return $result
        }
        catch {
            Write-Error "Failed to verify log integrity: $($_.Exception.Message)"
            throw
        }
    }
}

#endregion

#region Input Validation

<#
.SYNOPSIS
    Validates and normalizes a file path

.PARAMETER Path
    The path to validate

.EXAMPLE
    $safePath = Test-SafePath -Path "C:\PKI\Consolidation\config"
#>
function Test-SafePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    
    process {
        try {
            # Block path traversal
            if ($Path -match '\.\.' -or $Path -match '\\\\') {
                throw "Invalid path detected (path traversal attempt): $Path"
            }
            
            # Block UNC paths (optional - can be configured)
            if ($Path -match '^\\\\' -and -not $Global:AllowUNCPaths) {
                throw "UNC paths not allowed: $Path"
            }
            
            # Normalize path
            $normalized = [System.IO.Path]::GetFullPath($Path)
            
            Write-Verbose "Path validated and normalized: $normalized"
            return $normalized
        }
        catch [System.ArgumentException] {
            throw "Invalid path format: $Path"
        }
        catch {
            throw "Path validation failed: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Validates a filename for invalid characters

.PARAMETER FileName
    The filename to validate

.EXAMPLE
    $safeFilename = Test-SafeFileName -FileName "CA-Report.csv"
#>
function Test-SafeFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
    )
    
    process {
        # Block invalid characters
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        foreach ($char in $invalidChars) {
            if ($FileName.Contains($char)) {
                throw "Invalid file name character detected: $char in $FileName"
            }
        }
        
        # Block reserved names
        $reservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 
            'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 
            'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
        
        $nameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
        if ($nameWithoutExtension.ToUpper() -in $reservedNames) {
            throw "Reserved file name not allowed: $FileName"
        }
        
        Write-Verbose "Filename validated: $FileName"
        return $FileName
    }
}

<#
.SYNOPSIS
    Validates a CA name for safe characters only

.PARAMETER CAName
    The CA name to validate

.EXAMPLE
    $safeCAName = Test-SafeCAName -CAName "Contoso-RootCA"
#>
function Test-SafeCAName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CAName
    )
    
    process {
        # Only allow alphanumeric, dash, underscore
        if ($CAName -notmatch '^[a-zA-Z0-9\-_]+$') {
            throw "Invalid CA name format: $CAName (only alphanumeric, dash, underscore allowed)"
        }
        
        Write-Verbose "CA name validated: $CAName"
        return $CAName
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Set-PKICredential',
    'Get-PKICredential',
    'Get-AzureKeyVaultSecret',
    'Test-RequiredPrivileges',
    'Set-SecureDirectoryPermissions',
    'Set-SecureLogFilePermissions',
    'Write-SecureLog',
    'Test-LogIntegrity',
    'Test-SafePath',
    'Test-SafeFileName',
    'Test-SafeCAName'
)


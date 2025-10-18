<#
.SYNOPSIS
    PKI-Consolidation Performance Optimization Module

.DESCRIPTION
    Provides performance enhancements for PKI operations including:
    - Parallel CA processing (PowerShell 7+)
    - Certificate store caching
    - Performance monitoring and metrics

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Version: 1.0.0
    Requires: PowerShell 5.1+ (parallel features require 7.0+)
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest

#region Certificate Store Cache

# Global cache for certificate stores
$script:CertStoreCache = @{}
$script:CacheLock = [System.Threading.ReaderWriterLockSlim]::new()
$script:CacheExpiration = New-TimeSpan -Minutes 15

<#
.SYNOPSIS
    Gets a certificate store with caching support

.DESCRIPTION
    Retrieves a certificate store and caches it for improved performance.
    Cached stores are automatically refreshed after the expiration period.

.PARAMETER StoreName
    Name of the certificate store (e.g., 'My', 'Root', 'CA')

.PARAMETER StoreLocation
    Location of the store (CurrentUser or LocalMachine)

.PARAMETER ForceRefresh
    Forces a cache refresh even if the cached entry is still valid

.EXAMPLE
    Get-CachedCertStore -StoreName 'Root' -StoreLocation LocalMachine
#>
function Get-CachedCertStore {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Store])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('My', 'Root', 'CA', 'Trust', 'Disallowed', 'TrustedPeople', 'TrustedPublisher')]
        [string]$StoreName,
        
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.StoreLocation]$StoreLocation,
        
        [switch]$ForceRefresh
    )
    
    $cacheKey = "${StoreLocation}_${StoreName}"
    
    $script:CacheLock.EnterUpgradeableReadLock()
    try {
        $cacheEntry = $script:CertStoreCache[$cacheKey]
        $now = Get-Date
        
        # Check if we have a valid cached entry
        if (-not $ForceRefresh -and $cacheEntry -and 
            ($now - $cacheEntry.Timestamp) -lt $script:CacheExpiration) {
            Write-Verbose "Cache HIT for $cacheKey"
            return $cacheEntry.Store
        }
        
        Write-Verbose "Cache MISS for $cacheKey - loading store"
        
        # Need to refresh - acquire write lock
        $script:CacheLock.EnterWriteLock()
        try {
            # Open and cache the store
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
                $StoreName, $StoreLocation
            )
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
            
            $script:CertStoreCache[$cacheKey] = @{
                Store = $store
                Timestamp = $now
            }
            
            return $store
        }
        finally {
            $script:CacheLock.ExitWriteLock()
        }
    }
    finally {
        $script:CacheLock.ExitUpgradeableReadLock()
    }
}

<#
.SYNOPSIS
    Finds a certificate in cached stores

.DESCRIPTION
    Searches for certificates in cached stores using thumbprint or subject name

.PARAMETER Thumbprint
    Certificate thumbprint to search for

.PARAMETER SubjectName
    Certificate subject name to search for (partial match)

.PARAMETER StoreName
    Name of the certificate store to search

.PARAMETER StoreLocation
    Location of the store

.EXAMPLE
    Find-CachedCertificate -Thumbprint '1234567890ABCDEF...' -StoreName 'My' -StoreLocation LocalMachine
#>
function Find-CachedCertificate {
    [CmdletBinding(DefaultParameterSetName='ByThumbprint')]
    param(
        [Parameter(Mandatory, ParameterSetName='ByThumbprint')]
        [string]$Thumbprint,
        
        [Parameter(Mandatory, ParameterSetName='BySubject')]
        [string]$SubjectName,
        
        [Parameter(Mandatory)]
        [ValidateSet('My', 'Root', 'CA', 'Trust', 'Disallowed', 'TrustedPeople', 'TrustedPublisher')]
        [string]$StoreName,
        
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.StoreLocation]$StoreLocation
    )
    
    $store = Get-CachedCertStore -StoreName $StoreName -StoreLocation $StoreLocation
    
    if ($PSCmdlet.ParameterSetName -eq 'ByThumbprint') {
        $certs = $store.Certificates.Find(
            [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
            $Thumbprint,
            $false
        )
    }
    else {
        $certs = $store.Certificates.Find(
            [System.Security.Cryptography.X509Certificates.X509FindType]::FindBySubjectName,
            $SubjectName,
            $false
        )
    }
    
    return $certs
}

<#
.SYNOPSIS
    Clears the certificate store cache

.DESCRIPTION
    Clears cached certificate stores and closes open store handles

.EXAMPLE
    Clear-CertStoreCache
#>
function Clear-CertStoreCache {
    [CmdletBinding()]
    param()
    
    $script:CacheLock.EnterWriteLock()
    try {
        foreach ($entry in $script:CertStoreCache.Values) {
            if ($entry.Store) {
                try {
                    $entry.Store.Close()
                    $entry.Store.Dispose()
                }
                catch {
                    Write-Warning "Failed to close store: $_"
                }
            }
        }
        $script:CertStoreCache.Clear()
        Write-Verbose "Certificate store cache cleared"
    }
    finally {
        $script:CacheLock.ExitWriteLock()
    }
}

#endregion

#region Parallel Processing

<#
.SYNOPSIS
    Tests if parallel processing is available

.DESCRIPTION
    Checks if the current PowerShell version supports ForEach-Object -Parallel

.EXAMPLE
    Test-ParallelSupport
#>
function Test-ParallelSupport {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    return $PSVersionTable.PSVersion.Major -ge 7
}

<#
.SYNOPSIS
    Processes CAs in parallel using PowerShell 7+ features

.DESCRIPTION
    Executes a script block against multiple CAs in parallel for improved performance.
    Falls back to sequential processing on PowerShell 5.1.

.PARAMETER CAList
    Array of CA objects to process

.PARAMETER ScriptBlock
    Script block to execute for each CA

.PARAMETER ThrottleLimit
    Maximum number of parallel operations (default: 5)

.PARAMETER TimeoutSeconds
    Timeout for each operation in seconds (default: 300)

.EXAMPLE
    $cas = @($ca1, $ca2, $ca3)
    Invoke-ParallelCAProcessing -CAList $cas -ScriptBlock {
        param($CA)
        # Process CA
        Test-Connection $CA.Hostname
    }
#>
function Invoke-ParallelCAProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$CAList,
        
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [ValidateRange(1, 20)]
        [int]$ThrottleLimit = 5,
        
        [ValidateRange(30, 3600)]
        [int]$TimeoutSeconds = 300,
        
        [hashtable]$ArgumentList = @{}
    )
    
    if (-not $CAList -or $CAList.Count -eq 0) {
        Write-Warning "No CAs to process"
        return @()
    }
    
    Write-Verbose "Processing $($CAList.Count) CAs (Throttle: $ThrottleLimit)"
    
    if (Test-ParallelSupport) {
        Write-Verbose "Using PowerShell 7+ parallel processing"
        
        $results = $CAList | ForEach-Object -Parallel {
            $ca = $_
            $sb = $using:ScriptBlock
            $args = $using:ArgumentList
            
            try {
                # Execute the script block with timeout
                $job = Start-Job -ScriptBlock $sb -ArgumentList $ca, $args
                
                if (Wait-Job -Job $job -Timeout $using:TimeoutSeconds) {
                    $result = Receive-Job -Job $job
                    Remove-Job -Job $job -Force
                    
                    [pscustomobject]@{
                        CA = $ca
                        Success = $true
                        Result = $result
                        Error = $null
                    }
                }
                else {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force
                    
                    [pscustomobject]@{
                        CA = $ca
                        Success = $false
                        Result = $null
                        Error = "Operation timed out after $($using:TimeoutSeconds) seconds"
                    }
                }
            }
            catch {
                [pscustomobject]@{
                    CA = $ca
                    Success = $false
                    Result = $null
                    Error = $_.Exception.Message
                }
            }
        } -ThrottleLimit $ThrottleLimit
        
        return $results
    }
    else {
        Write-Verbose "Using sequential processing (PowerShell 5.1)"
        
        $results = foreach ($ca in $CAList) {
            try {
                $result = & $ScriptBlock $ca $ArgumentList
                
                [pscustomobject]@{
                    CA = $ca
                    Success = $true
                    Result = $result
                    Error = $null
                }
            }
            catch {
                [pscustomobject]@{
                    CA = $ca
                    Success = $false
                    Result = $null
                    Error = $_.Exception.Message
                }
            }
        }
        
        return $results
    }
}

#endregion

#region Performance Monitoring

<#
.SYNOPSIS
    Starts a performance measurement

.DESCRIPTION
    Begins timing an operation for performance monitoring

.PARAMETER OperationName
    Name of the operation being measured

.EXAMPLE
    $timer = Start-PerformanceTimer -OperationName "CA Audit"
#>
function Start-PerformanceTimer {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$OperationName
    )
    
    return @{
        Name = $OperationName
        StartTime = Get-Date
        Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    }
}

<#
.SYNOPSIS
    Stops a performance measurement

.DESCRIPTION
    Stops timing an operation and returns performance metrics

.PARAMETER Timer
    Timer object from Start-PerformanceTimer

.EXAMPLE
    $metrics = Stop-PerformanceTimer -Timer $timer
    Write-Host "Operation took $($metrics.ElapsedSeconds) seconds"
#>
function Stop-PerformanceTimer {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Timer
    )
    
    $Timer.Stopwatch.Stop()
    $endTime = Get-Date
    
    return [pscustomobject]@{
        Name = $Timer.Name
        StartTime = $Timer.StartTime
        EndTime = $endTime
        ElapsedMilliseconds = $Timer.Stopwatch.ElapsedMilliseconds
        ElapsedSeconds = [math]::Round($Timer.Stopwatch.Elapsed.TotalSeconds, 2)
        ElapsedMinutes = [math]::Round($Timer.Stopwatch.Elapsed.TotalMinutes, 2)
    }
}

<#
.SYNOPSIS
    Measures the performance of a script block

.DESCRIPTION
    Executes a script block and returns both the result and performance metrics

.PARAMETER ScriptBlock
    Script block to measure

.PARAMETER OperationName
    Name of the operation for logging

.EXAMPLE
    $result = Measure-OperationPerformance -OperationName "Export Certificates" -ScriptBlock {
        Get-ChildItem Cert:\LocalMachine\My
    }
    Write-Host "Found $($result.Result.Count) certificates in $($result.Metrics.ElapsedSeconds)s"
#>
function Measure-OperationPerformance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory)]
        [string]$OperationName
    )
    
    $timer = Start-PerformanceTimer -OperationName $OperationName
    
    try {
        $result = & $ScriptBlock
        $metrics = Stop-PerformanceTimer -Timer $timer
        
        return [pscustomobject]@{
            Success = $true
            Result = $result
            Metrics = $metrics
            Error = $null
        }
    }
    catch {
        $metrics = Stop-PerformanceTimer -Timer $timer
        
        return [pscustomobject]@{
            Success = $false
            Result = $null
            Metrics = $metrics
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region Module Cleanup

# Cleanup on module removal
$ExecutionContext.SessionState.Module.OnRemove = {
    Clear-CertStoreCache
    
    if ($script:CacheLock) {
        $script:CacheLock.Dispose()
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Get-CachedCertStore',
    'Find-CachedCertificate',
    'Clear-CertStoreCache',
    'Test-ParallelSupport',
    'Invoke-ParallelCAProcessing',
    'Start-PerformanceTimer',
    'Stop-PerformanceTimer',
    'Measure-OperationPerformance'
)


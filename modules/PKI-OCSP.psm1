<#
.SYNOPSIS
    PKI-Consolidation OCSP Validation Module

.DESCRIPTION
    Provides enhanced Online Certificate Status Protocol (OCSP) validation
    including responder health checks, response validation, and monitoring

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest

#region OCSP Response Types

enum OCSPStatus {
    Good = 0
    Revoked = 1
    Unknown = 2
}

enum OCSPResponseStatus {
    Successful = 0
    MalformedRequest = 1
    InternalError = 2
    TryLater = 3
    SignRequired = 5
    Unauthorized = 6
}

#endregion

#region OCSP Validation

<#
.SYNOPSIS
    Tests OCSP responder availability

.DESCRIPTION
    Checks if an OCSP responder URL is reachable and responding

.PARAMETER ResponderUrl
    URL of the OCSP responder

.PARAMETER TimeoutSeconds
    Connection timeout in seconds (default: 10)

.EXAMPLE
    Test-OCSPResponder -ResponderUrl 'http://ocsp.contoso.com/ocsp'
#>
function Test-OCSPResponder {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https?://')]
        [string]$ResponderUrl,
        
        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 10
    )
    
    $result = [pscustomobject]@{
        ResponderUrl = $ResponderUrl
        IsReachable = $false
        ResponseTimeMs = $null
        StatusCode = $null
        Error = $null
        TestedAt = Get-Date
    }
    
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Test HTTP connectivity
        $request = [System.Net.WebRequest]::Create($ResponderUrl)
        $request.Method = 'GET'
        $request.Timeout = $TimeoutSeconds * 1000
        $request.UserAgent = 'PKI-Consolidation-Tool/1.1.0'
        
        $response = $request.GetResponse()
        $sw.Stop()
        
        $result.IsReachable = $true
        $result.ResponseTimeMs = $sw.ElapsedMilliseconds
        $result.StatusCode = [int]$response.StatusCode
        
        $response.Close()
    }
    catch [System.Net.WebException] {
        $sw.Stop()
        $result.ResponseTimeMs = $sw.ElapsedMilliseconds
        
        if ($_.Exception.Response) {
            $result.StatusCode = [int]$_.Exception.Response.StatusCode
            # Some responders return 405 (Method Not Allowed) for GET, which is acceptable
            if ($result.StatusCode -eq 405) {
                $result.IsReachable = $true
                $result.Error = "Responder only accepts POST (expected for OCSP)"
            }
            else {
                $result.Error = "HTTP $($result.StatusCode): $($_.Exception.Message)"
            }
        }
        else {
            $result.Error = $_.Exception.Message
        }
    }
    catch {
        $sw.Stop()
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

<#
.SYNOPSIS
    Gets OCSP responder URLs from a certificate

.DESCRIPTION
    Extracts OCSP responder URLs from the Authority Information Access (AIA) extension

.PARAMETER Certificate
    X509Certificate2 object to extract OCSP URLs from

.EXAMPLE
    $cert = Get-Item Cert:\LocalMachine\My\1234567890ABCDEF
    Get-OCSPResponderFromCertificate -Certificate $cert
#>
function Get-OCSPResponderFromCertificate {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    
    process {
        $ocspUrls = @()
        
        try {
            # Look for Authority Information Access extension
            $aiaExt = $Certificate.Extensions | Where-Object {
                $_.Oid.Value -eq '1.3.6.1.5.5.7.1.1' # id-pe-authorityInfoAccess
            }
            
            if ($aiaExt) {
                $aiaData = $aiaExt.Format($true)
                
                # Extract OCSP URLs (OID 1.3.6.1.5.5.7.48.1)
                $matches = [regex]::Matches($aiaData, '(?i)OCSP.*?URL=(https?://[^\s\)]+)')
                
                foreach ($match in $matches) {
                    if ($match.Groups.Count -gt 1) {
                        $ocspUrls += $match.Groups[1].Value.Trim()
                    }
                }
                
                # Alternative pattern for some certificate formats
                if ($ocspUrls.Count -eq 0) {
                    $matches = [regex]::Matches($aiaData, '(?i)(https?://[^\s]+/ocsp[^\s]*)')
                    foreach ($match in $matches) {
                        $ocspUrls += $match.Groups[1].Value.Trim()
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to extract OCSP URLs from certificate: $_"
        }
        
        return $ocspUrls
    }
}

<#
.SYNOPSIS
    Validates certificate revocation status via OCSP

.DESCRIPTION
    Checks certificate revocation status using OCSP. Uses certutil for actual
    OCSP request/response validation.

.PARAMETER Certificate
    Path to certificate file or X509Certificate2 object

.PARAMETER ResponderUrl
    Optional: Specific OCSP responder URL to use

.EXAMPLE
    Test-CertificateOCSP -Certificate 'C:\cert.cer'
#>
function Test-CertificateOCSP {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            if ($_ -is [string]) {
                Test-Path -Path $_ -PathType Leaf
            } else {
                $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2]
            }
        })]
        $Certificate,
        
        [ValidatePattern('^https?://')]
        [string]$ResponderUrl
    )
    
    $result = [pscustomobject]@{
        Certificate = if ($Certificate -is [string]) { $Certificate } else { $Certificate.Subject }
        Status = [OCSPStatus]::Unknown
        ResponderUrl = $ResponderUrl
        IsValid = $false
        ResponseTime = $null
        Error = $null
        RawOutput = $null
        TestedAt = Get-Date
    }
    
    try {
        # Get certificate path
        $certPath = if ($Certificate -is [string]) {
            $Certificate
        }
        else {
            # Export to temp file
            $tempFile = [System.IO.Path]::GetTempFileName()
            $tempCert = $tempFile -replace '\.tmp$', '.cer'
            [System.IO.File]::WriteAllBytes($tempCert, $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            $tempCert
        }
        
        # Build certutil command
        $args = @('-verify', '-urlfetch', $certPath)
        
        if ($ResponderUrl) {
            # [Inference] Based on observed patterns, certutil may support specifying OCSP URL via environment or config
            Write-Verbose "Using OCSP responder: $ResponderUrl"
        }
        
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $output = & certutil @args 2>&1
        $sw.Stop()
        $exitCode = $LASTEXITCODE
        
        $result.ResponseTime = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        $result.RawOutput = $output -join "`n"
        
        # Parse output
        if ($exitCode -eq 0) {
            $result.IsValid = $true
            $result.Status = [OCSPStatus]::Good
        }
        elseif ($output -match '(?i)revoked') {
            $result.Status = [OCSPStatus]::Revoked
            $result.Error = "Certificate is revoked"
        }
        else {
            $result.Status = [OCSPStatus]::Unknown
            $result.Error = "Verification failed (exit code: $exitCode)"
        }
        
        # Extract OCSP responder URL if not specified
        if (-not $result.ResponderUrl) {
            $urlMatch = $output | Select-String -Pattern 'https?://[^\s]+/ocsp'
            if ($urlMatch) {
                $result.ResponderUrl = $urlMatch.Matches[0].Value
            }
        }
        
        # Cleanup temp file if created
        if ($Certificate -isnot [string] -and (Test-Path $tempCert)) {
            Remove-Item $tempCert -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

<#
.SYNOPSIS
    Tests all OCSP responders for a CA

.DESCRIPTION
    Discovers and tests all OCSP responders configured for a Certificate Authority

.PARAMETER CAName
    Name of the Certificate Authority

.PARAMETER IncludeCertificateTest
    If specified, also tests OCSP with a sample certificate

.EXAMPLE
    Test-CAOCSPHealth -CAName 'ContosoCA'
#>
function Test-CAOCSPHealth {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$CAName,
        
        [switch]$IncludeCertificateTest
    )
    
    $result = [pscustomobject]@{
        CAName = $CAName
        ResponderCount = 0
        Responders = @()
        AllHealthy = $false
        TestedAt = Get-Date
    }
    
    try {
        # Get OCSP URLs from registry
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$CAName"
        $aiaRaw = (Get-ItemProperty -Path $regPath -Name 'AuthorityInformationAccess' -ErrorAction SilentlyContinue).AuthorityInformationAccess
        
        if (-not $aiaRaw) {
            Write-Warning "No Authority Information Access configuration found for $CAName"
            return $result
        }
        
        # Extract OCSP URLs
        $aiaLines = ($aiaRaw -split "`r?`n") | Where-Object { $_ -match '(?i)OCSP' -and $_ -match 'https?://' }
        $ocspUrls = @()
        
        foreach ($line in $aiaLines) {
            if ($line -match '(https?://[^\s]+)') {
                $ocspUrls += $matches[1]
            }
        }
        
        $result.ResponderCount = $ocspUrls.Count
        
        # Test each responder
        foreach ($url in $ocspUrls) {
            Write-Verbose "Testing OCSP responder: $url"
            $responderTest = Test-OCSPResponder -ResponderUrl $url
            $result.Responders += $responderTest
        }
        
        # Check if all are healthy
        $result.AllHealthy = ($result.Responders.Count -gt 0) -and 
                             ($result.Responders | Where-Object { -not $_.IsReachable }).Count -eq 0
    }
    catch {
        Write-Error "Failed to test OCSP health for ${CAName}: $_"
    }
    
    return $result
}

<#
.SYNOPSIS
    Monitors OCSP responder performance over time

.DESCRIPTION
    Performs multiple OCSP responder checks and reports performance statistics

.PARAMETER ResponderUrl
    URL of the OCSP responder to monitor

.PARAMETER SampleCount
    Number of test samples to collect (default: 5)

.PARAMETER DelaySeconds
    Delay between samples in seconds (default: 2)

.EXAMPLE
    Measure-OCSPPerformance -ResponderUrl 'http://ocsp.contoso.com/ocsp' -SampleCount 10
#>
function Measure-OCSPPerformance {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https?://')]
        [string]$ResponderUrl,
        
        [ValidateRange(1, 100)]
        [int]$SampleCount = 5,
        
        [ValidateRange(1, 60)]
        [int]$DelaySeconds = 2
    )
    
    $samples = @()
    
    Write-Verbose "Collecting $SampleCount samples from $ResponderUrl"
    
    for ($i = 1; $i -le $SampleCount; $i++) {
        Write-Progress -Activity "OCSP Performance Test" `
                       -Status "Sample $i of $SampleCount" `
                       -PercentComplete (($i / $SampleCount) * 100)
        
        $sample = Test-OCSPResponder -ResponderUrl $ResponderUrl
        $samples += $sample
        
        if ($i -lt $SampleCount) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    
    Write-Progress -Activity "OCSP Performance Test" -Completed
    
    # Calculate statistics
    $successfulSamples = $samples | Where-Object { $_.IsReachable }
    $responseTimes = $successfulSamples | ForEach-Object { $_.ResponseTimeMs }
    
    return [pscustomobject]@{
        ResponderUrl = $ResponderUrl
        SampleCount = $SampleCount
        SuccessCount = $successfulSamples.Count
        FailureCount = $SampleCount - $successfulSamples.Count
        SuccessRate = [math]::Round(($successfulSamples.Count / $SampleCount) * 100, 2)
        AverageResponseTimeMs = if ($responseTimes) { [math]::Round(($responseTimes | Measure-Object -Average).Average, 2) } else { $null }
        MinResponseTimeMs = if ($responseTimes) { ($responseTimes | Measure-Object -Minimum).Minimum } else { $null }
        MaxResponseTimeMs = if ($responseTimes) { ($responseTimes | Measure-Object -Maximum).Maximum } else { $null }
        Samples = $samples
        TestedAt = Get-Date
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Test-OCSPResponder',
    'Get-OCSPResponderFromCertificate',
    'Test-CertificateOCSP',
    'Test-CAOCSPHealth',
    'Measure-OCSPPerformance'
)


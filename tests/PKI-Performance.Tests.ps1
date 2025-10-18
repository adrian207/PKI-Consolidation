<#
.SYNOPSIS
    Pester tests for PKI-Performance module

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Requires: Pester 5.0+
#>

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\modules\PKI-Performance.psm1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    }
    else {
        throw "Module not found: $modulePath"
    }
}

Describe 'PKI-Performance Module' {
    Context 'Module Import' {
        It 'Should import successfully' {
            Get-Module PKI-Performance | Should -Not -BeNullOrEmpty
        }
        
        It 'Should export expected functions' {
            $expectedFunctions = @(
                'Get-CachedCertStore',
                'Find-CachedCertificate',
                'Clear-CertStoreCache',
                'Test-ParallelSupport',
                'Invoke-ParallelCAProcessing',
                'Start-PerformanceTimer',
                'Stop-PerformanceTimer',
                'Measure-OperationPerformance'
            )
            
            $exportedFunctions = (Get-Command -Module PKI-Performance).Name
            
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }
    
    Context 'Certificate Store Caching' {
        Describe 'Get-CachedCertStore' {
            It 'Should retrieve certificate store' {
                $store = Get-CachedCertStore -StoreName 'Root' -StoreLocation LocalMachine
                
                $store | Should -Not -BeNullOrEmpty
                $store | Should -BeOfType [System.Security.Cryptography.X509Certificates.X509Store]
            }
            
            It 'Should cache repeated calls' {
                $store1 = Get-CachedCertStore -StoreName 'Root' -StoreLocation LocalMachine
                $store2 = Get-CachedCertStore -StoreName 'Root' -StoreLocation LocalMachine
                
                # Both calls should return the same cached instance
                $store1 | Should -Be $store2
            }
            
            It 'Should support force refresh' {
                $store1 = Get-CachedCertStore -StoreName 'Root' -StoreLocation LocalMachine
                $store2 = Get-CachedCertStore -StoreName 'Root' -StoreLocation LocalMachine -ForceRefresh
                
                $store2 | Should -Not -BeNullOrEmpty
            }
        }
        
        Describe 'Clear-CertStoreCache' {
            It 'Should clear cache without errors' {
                # Populate cache
                $null = Get-CachedCertStore -StoreName 'Root' -StoreLocation LocalMachine
                
                # Clear cache
                { Clear-CertStoreCache } | Should -Not -Throw
            }
        }
    }
    
    Context 'Parallel Processing' {
        Describe 'Test-ParallelSupport' {
            It 'Should return boolean' {
                $result = Test-ParallelSupport
                $result | Should -BeOfType [bool]
            }
            
            It 'Should return true for PowerShell 7+' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
                $result = Test-ParallelSupport
                $result | Should -Be $true
            }
            
            It 'Should return false for PowerShell 5.1' -Skip:($PSVersionTable.PSVersion.Major -ge 7) {
                $result = Test-ParallelSupport
                $result | Should -Be $false
            }
        }
        
        Describe 'Invoke-ParallelCAProcessing' {
            It 'Should process CA list' {
                $caList = @(
                    [pscustomobject]@{ Name = 'CA1'; Hostname = 'ca1.contoso.com' }
                    [pscustomobject]@{ Name = 'CA2'; Hostname = 'ca2.contoso.com' }
                )
                
                $scriptBlock = {
                    param($CA, $Args)
                    return "Processed: $($CA.Name)"
                }
                
                $results = Invoke-ParallelCAProcessing -CAList $caList -ScriptBlock $scriptBlock
                
                $results | Should -Not -BeNullOrEmpty
                $results.Count | Should -Be 2
                $results[0].CA.Name | Should -Match 'CA[12]'
            }
            
            It 'Should handle errors gracefully' {
                $caList = @(
                    [pscustomobject]@{ Name = 'CA1' }
                )
                
                $scriptBlock = {
                    param($CA)
                    throw "Simulated error"
                }
                
                $results = Invoke-ParallelCAProcessing -CAList $caList -ScriptBlock $scriptBlock
                
                $results[0].Success | Should -Be $false
                $results[0].Error | Should -Not -BeNullOrEmpty
            }
            
            It 'Should respect throttle limit' {
                $caList = 1..10 | ForEach-Object {
                    [pscustomobject]@{ Name = "CA$_" }
                }
                
                $scriptBlock = {
                    param($CA)
                    Start-Sleep -Milliseconds 100
                    return $CA.Name
                }
                
                { Invoke-ParallelCAProcessing -CAList $caList -ScriptBlock $scriptBlock -ThrottleLimit 3 } | Should -Not -Throw
            }
        }
    }
    
    Context 'Performance Monitoring' {
        Describe 'Start-PerformanceTimer' {
            It 'Should create timer object' {
                $timer = Start-PerformanceTimer -OperationName 'Test'
                
                $timer | Should -Not -BeNullOrEmpty
                $timer.Name | Should -Be 'Test'
                $timer.StartTime | Should -BeOfType [DateTime]
                $timer.Stopwatch | Should -Not -BeNullOrEmpty
            }
        }
        
        Describe 'Stop-PerformanceTimer' {
            It 'Should return metrics' {
                $timer = Start-PerformanceTimer -OperationName 'Test'
                Start-Sleep -Milliseconds 100
                $metrics = Stop-PerformanceTimer -Timer $timer
                
                $metrics | Should -Not -BeNullOrEmpty
                $metrics.Name | Should -Be 'Test'
                $metrics.ElapsedMilliseconds | Should -BeGreaterThan 50
                $metrics.ElapsedSeconds | Should -BeOfType [double]
            }
        }
        
        Describe 'Measure-OperationPerformance' {
            It 'Should measure successful operations' {
                $result = Measure-OperationPerformance -OperationName 'Test' -ScriptBlock {
                    Start-Sleep -Milliseconds 50
                    return 'Success'
                }
                
                $result.Success | Should -Be $true
                $result.Result | Should -Be 'Success'
                $result.Metrics | Should -Not -BeNullOrEmpty
                $result.Metrics.ElapsedMilliseconds | Should -BeGreaterThan 0
            }
            
            It 'Should capture errors' {
                $result = Measure-OperationPerformance -OperationName 'Test' -ScriptBlock {
                    throw "Test error"
                }
                
                $result.Success | Should -Be $false
                $result.Error | Should -Not -BeNullOrEmpty
                $result.Metrics | Should -Not -BeNullOrEmpty
            }
        }
    }
}

AfterAll {
    # Cleanup
    Clear-CertStoreCache -ErrorAction SilentlyContinue
    Remove-Module PKI-Performance -Force -ErrorAction SilentlyContinue
}


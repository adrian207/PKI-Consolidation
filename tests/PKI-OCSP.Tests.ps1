<#
.SYNOPSIS
    Pester tests for PKI-OCSP module

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Requires: Pester 5.0+
#>

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\modules\PKI-OCSP.psm1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    }
    else {
        throw "Module not found: $modulePath"
    }
}

Describe 'PKI-OCSP Module' {
    Context 'Module Import' {
        It 'Should import successfully' {
            Get-Module PKI-OCSP | Should -Not -BeNullOrEmpty
        }
        
        It 'Should export expected functions' {
            $expectedFunctions = @(
                'Test-OCSPResponder',
                'Get-OCSPResponderFromCertificate',
                'Test-CertificateOCSP',
                'Test-CAOCSPHealth',
                'Measure-OCSPPerformance'
            )
            
            $exportedFunctions = (Get-Command -Module PKI-OCSP).Name
            
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }
    
    Context 'OCSP Responder Testing' {
        Describe 'Test-OCSPResponder' {
            It 'Should validate URL format' {
                { Test-OCSPResponder -ResponderUrl 'not-a-url' } | Should -Throw
            }
            
            It 'Should accept valid HTTP URL' {
                { Test-OCSPResponder -ResponderUrl 'http://ocsp.example.com/ocsp' } | Should -Not -Throw
            }
            
            It 'Should accept valid HTTPS URL' {
                { Test-OCSPResponder -ResponderUrl 'https://ocsp.example.com/ocsp' } | Should -Not -Throw
            }
            
            It 'Should return result object' {
                $result = Test-OCSPResponder -ResponderUrl 'http://ocsp.example.com/ocsp' -TimeoutSeconds 5
                
                $result | Should -Not -BeNullOrEmpty
                $result.ResponderUrl | Should -Be 'http://ocsp.example.com/ocsp'
                $result.IsReachable | Should -BeOfType [bool]
                $result.TestedAt | Should -BeOfType [DateTime]
            }
            
            It 'Should handle unreachable responders' {
                $result = Test-OCSPResponder -ResponderUrl 'http://ocsp.invalid.local/ocsp' -TimeoutSeconds 2
                
                $result.IsReachable | Should -Be $false
                $result.Error | Should -Not -BeNullOrEmpty
            }
            
            It 'Should measure response time' {
                $result = Test-OCSPResponder -ResponderUrl 'http://ocsp.example.com/ocsp'
                
                $result.PSObject.Properties.Name | Should -Contain 'ResponseTimeMs'
            }
        }
        
        Describe 'Measure-OCSPPerformance' {
            It 'Should collect multiple samples' {
                $result = Measure-OCSPPerformance -ResponderUrl 'http://ocsp.example.com/ocsp' -SampleCount 3 -DelaySeconds 1
                
                $result | Should -Not -BeNullOrEmpty
                $result.SampleCount | Should -Be 3
                $result.Samples | Should -HaveCount 3
            }
            
            It 'Should calculate statistics' {
                $result = Measure-OCSPPerformance -ResponderUrl 'http://ocsp.example.com/ocsp' -SampleCount 2 -DelaySeconds 1
                
                $result.PSObject.Properties.Name | Should -Contain 'SuccessRate'
                $result.PSObject.Properties.Name | Should -Contain 'AverageResponseTimeMs'
                $result.SuccessRate | Should -BeOfType [double]
            }
        }
    }
    
    Context 'Certificate OCSP Extraction' {
        Describe 'Get-OCSPResponderFromCertificate' {
            It 'Should accept X509Certificate2 objects' {
                # Get a test certificate
                $certs = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Select-Object -First 1
                
                if ($certs) {
                    { Get-OCSPResponderFromCertificate -Certificate $certs } | Should -Not -Throw
                }
                else {
                    Set-ItResult -Skipped -Because "No certificates available in test environment"
                }
            }
            
            It 'Should return array of URLs' {
                $certs = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | 
                         Where-Object { $_.Extensions | Where-Object { $_.Oid.Value -eq '1.3.6.1.5.5.7.1.1' } } |
                         Select-Object -First 1
                
                if ($certs) {
                    $result = Get-OCSPResponderFromCertificate -Certificate $certs
                    $result | Should -BeOfType [array]
                }
                else {
                    Set-ItResult -Skipped -Because "No certificates with AIA extension available"
                }
            }
        }
    }
    
    Context 'CA OCSP Health' {
        Describe 'Test-CAOCSPHealth' {
            It 'Should require CA name' {
                { Test-CAOCSPHealth -CAName '' } | Should -Throw
            }
            
            It 'Should return health object' -Skip {
                # This test requires a real CA configuration
                # Skipped by default as it's environment-specific
                
                $result = Test-CAOCSPHealth -CAName 'TestCA'
                
                $result | Should -Not -BeNullOrEmpty
                $result.CAName | Should -Be 'TestCA'
                $result.ResponderCount | Should -BeOfType [int]
            }
        }
    }
}

AfterAll {
    # Cleanup
    Remove-Module PKI-OCSP -Force -ErrorAction SilentlyContinue
}


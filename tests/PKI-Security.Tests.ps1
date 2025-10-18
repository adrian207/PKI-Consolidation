<#
.SYNOPSIS
    Pester tests for PKI-Security module

.NOTES
    Author: Adrian Johnson <adrian207@gmail.com>
    Requires: Pester 5.0+
#>

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\modules\PKI-Security.psm1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    }
    else {
        throw "Module not found: $modulePath"
    }
}

Describe 'PKI-Security Module' {
    Context 'Module Import' {
        It 'Should import successfully' {
            Get-Module PKI-Security | Should -Not -BeNullOrEmpty
        }
        
        It 'Should export expected functions' {
            $expectedFunctions = @(
                'Get-PKICredential',
                'Set-PKICredential',
                'Remove-PKICredential',
                'Test-RequiredPrivileges',
                'Set-SecureDirectoryPermissions',
                'Write-SecureLog',
                'Test-LogIntegrity',
                'Test-SafePath',
                'Test-SafeFileName',
                'Test-SafeCAName'
            )
            
            $exportedFunctions = (Get-Command -Module PKI-Security).Name
            
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }
    
    Context 'Input Validation' {
        Describe 'Test-SafePath' {
            It 'Should accept valid relative paths' {
                { Test-SafePath -Path 'folder\file.txt' } | Should -Not -Throw
            }
            
            It 'Should accept valid absolute paths' {
                { Test-SafePath -Path 'C:\Windows\System32' } | Should -Not -Throw
            }
            
            It 'Should reject null traversal attempts' {
                { Test-SafePath -Path 'folder\..\..\..\..\..\windows\system32' } | Should -Throw
            }
            
            It 'Should reject UNC paths with suspicious patterns' {
                { Test-SafePath -Path '\\evil.com\share\file.exe' } | Should -Throw
            }
            
            It 'Should reject paths with null bytes' {
                { Test-SafePath -Path "file`0.txt" } | Should -Throw
            }
        }
        
        Describe 'Test-SafeFileName' {
            It 'Should accept valid filenames' {
                $result = Test-SafeFileName -FileName 'document.txt'
                $result | Should -Be 'document.txt'
            }
            
            It 'Should sanitize invalid characters' {
                $result = Test-SafeFileName -FileName 'file<>:"|?*.txt'
                $result | Should -Not -Match '[<>:"|?*]'
            }
            
            It 'Should reject empty filenames' {
                { Test-SafeFileName -FileName '' } | Should -Throw
            }
            
            It 'Should handle long filenames' {
                $longName = 'a' * 300 + '.txt'
                $result = Test-SafeFileName -FileName $longName
                $result.Length | Should -BeLessOrEqual 255
            }
        }
        
        Describe 'Test-SafeCAName' {
            It 'Should accept valid CA names' {
                $result = Test-SafeCAName -CAName 'ContosoRootCA'
                $result | Should -Be 'ContosoRootCA'
            }
            
            It 'Should sanitize dangerous characters' {
                $result = Test-SafeCAName -CAName 'CA;DROP TABLE--'
                $result | Should -Not -Match '[;<>"]'
            }
        }
    }
    
    Context 'Logging' {
        Describe 'Write-SecureLog' {
            BeforeEach {
                $script:testLogPath = Join-Path $TestDrive 'test.log'
                
                # Generate test HMAC key
                $script:testHMACKey = ConvertTo-SecureString -String ([guid]::NewGuid().ToString()) -AsPlainText -Force
            }
            
            AfterEach {
                if (Test-Path $script:testLogPath) {
                    Remove-Item $script:testLogPath -Force
                }
            }
            
            It 'Should write log entries' {
                Write-SecureLog -Message 'Test message' -Level 'INFO' -SessionID 'TEST123' -LogPath $script:testLogPath
                
                Test-Path $script:testLogPath | Should -Be $true
                $content = Get-Content $script:testLogPath
                $content | Should -Not -BeNullOrEmpty
                $content | Should -Match 'Test message'
            }
            
            It 'Should include HMAC when key provided' {
                Write-SecureLog -Message 'Test' -Level 'INFO' -SessionID 'TEST123' -LogPath $script:testLogPath -HMACKey $script:testHMACKey
                
                $content = Get-Content $script:testLogPath
                $content | Should -Match 'HMAC='
            }
            
            It 'Should include session ID' {
                Write-SecureLog -Message 'Test' -Level 'INFO' -SessionID 'SESSION123' -LogPath $script:testLogPath
                
                $content = Get-Content $script:testLogPath
                $content | Should -Match 'SESSION123'
            }
        }
        
        Describe 'Test-LogIntegrity' {
            It 'Should detect tampered logs' {
                # Create a log with HMAC
                $hmacKey = ConvertTo-SecureString -String ([guid]::NewGuid().ToString()) -AsPlainText -Force
                $logPath = Join-Path $TestDrive 'integrity-test.log'
                
                Write-SecureLog -Message 'Original message' -Level 'INFO' -SessionID 'TEST' -LogPath $logPath -HMACKey $hmacKey
                
                # Tamper with the log
                $content = Get-Content $logPath
                $tamperedContent = $content -replace 'Original message', 'Tampered message'
                $tamperedContent | Set-Content $logPath
                
                # Verify integrity check fails
                $result = Test-LogIntegrity -LogPath $logPath -HMACKey $hmacKey
                $result.IsValid | Should -Be $false
            }
        }
    }
    
    Context 'File System Security' {
        Describe 'Set-SecureDirectoryPermissions' {
            BeforeEach {
                $script:testDir = Join-Path $TestDrive 'secure-folder'
                New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
            }
            
            It 'Should set restrictive permissions' -Skip:(-not $IsWindows -and -not ($PSVersionTable.PSVersion.Major -le 5)) {
                Set-SecureDirectoryPermissions -Path $script:testDir
                
                $acl = Get-Acl $script:testDir
                $acl | Should -Not -BeNullOrEmpty
            }
            
            It 'Should remove inheritance' -Skip:(-not $IsWindows -and -not ($PSVersionTable.PSVersion.Major -le 5)) {
                Set-SecureDirectoryPermissions -Path $script:testDir
                
                $acl = Get-Acl $script:testDir
                $acl.AreAccessRulesProtected | Should -Be $true
            }
        }
    }
    
    Context 'Privilege Validation' {
        Describe 'Test-RequiredPrivileges' {
            It 'Should return a result object' {
                $result = Test-RequiredPrivileges
                
                $result | Should -Not -BeNullOrEmpty
                $result.IsLocalAdmin | Should -BeOfType [bool]
                $result.HasRequiredPrivileges | Should -BeOfType [bool]
            }
            
            It 'Should include privilege details' {
                $result = Test-RequiredPrivileges
                
                $result.PSObject.Properties.Name | Should -Contain 'IsLocalAdmin'
                $result.PSObject.Properties.Name | Should -Contain 'HasRequiredPrivileges'
            }
        }
    }
}

AfterAll {
    # Cleanup
    Remove-Module PKI-Security -Force -ErrorAction SilentlyContinue
}


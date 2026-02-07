$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
# Import module
Import-Module "$here\..\Repair-TakeControlAgent.psd1" -Force

Describe "Repair-TakeControlAgent Module" {
    It "Should export public functions" {
        Get-Command -Module Repair-TakeControlAgent -Name Repair-TakeControlAgent | Should -Not -BeNullOrEmpty
        Get-Command -Module Repair-TakeControlAgent -Name Invoke-TakeControlChaos | Should -Not -BeNullOrEmpty
    }

    Context "Repair-TakeControlAgent Command" {
        It "Should have correct parameters" {
            $cmd = Get-Command Repair-TakeControlAgent
            $cmd.Parameters.Keys | Should -Contain "OperationMode"
            $cmd.Parameters.Keys | Should -Contain "TargetVersion"
            $cmd.Parameters.Keys | Should -Contain "RestartNcentralAgent"
        }
    }

    Context "Invoke-TakeControlChaos Command" {
        It "Should have correct parameters" {
            $cmd = Get-Command Invoke-TakeControlChaos
            $cmd.Parameters.Keys | Should -Contain "Scenario"
            $cmd.Parameters.Keys | Should -Contain "AllowDestruction"
        }
    }
}

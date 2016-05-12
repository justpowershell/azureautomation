<#
.SYNOPSIS
    Connects to Azure and shuts down and deallocates all VMs in the specified Azure subscription.
.DESCRIPTION
    This runbook creates or updates a run once schedule which is linked to an other runbook. Any previous
    schedule with the same name are replaced, which makes it possible to postpone the invokation of that
    other runbook.
	
    The Parameters-paramerer must be formatted as follows: "param1=value1`nparam2=value2". Note that only
    string parameteters are allowed! PowerShell contains no convenient way to convert string data to a
    hash-table with primitive data types.

    Note! This runbook requires the module Azure.Automation, which is not part of the deafault modules
    in Azure Automation. To install it, you can upload a copy of your local module which is located
    C:\Program Files\WindowsPowerShell\Modules\AzureRM.Automation\1.0.1. Make sure that the archive
    that you upload contains the module files directly under its root.
#>

workflow Set-AzureRmAutomationScheduledRunbook {
    param(
        [string]$AutomationPSCredentialName = "DefaultAzureCredential",
        [string]$SubscriptionId = "230e5e8e-a1a5-4ff2-a428-df4a621fb489",
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory=$true)]
        [string]$AutomationAccountName,
        [Parameter(Mandatory=$true)]
        [string]$ScheduleName,
        [Parameter(Mandatory=$true)]
        [string]$RunbookName,
        [int]$MinutesToScheduleAhead = 180,
        [string]$Parameters
    )

    $cred = Get-AutomationPSCredential -Name $AutomationPSCredentialName
    # Connect to Azure (Login-AzureRmAccount works, but Select-AzureRmSubscription does not due to some dll-failure!)
    Add-AzureRmAccount -Credential $cred -SubscriptionId $SubscriptionId

    $schedule = Get-AzureRmAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName |
        Where-Object -FilterScript { $_.Name -eq $ScheduleName }
    if ($schedule) {
        Remove-AzureRmAutomationSchedule -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName ` -Name $ScheduleName -Force
    }
    New-AzureRmAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
        -Name $ScheduleName -StartTime ((Get-Date).AddMinutes($MinutesToScheduleAhead)) -OneTime
    $parametersHash = ConvertFrom-StringData -StringData ($Parameters -replace '`n',"`n")
    Register-AzureRmAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
        -RunbookName $RunbookName -ScheduleName $ScheduleName -Parameters $parametersHash
}
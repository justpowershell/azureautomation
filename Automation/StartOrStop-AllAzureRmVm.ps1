<#
.SYNOPSIS
    Connects to Azure and either starts-, or shuts down and deallocates all VMs in the
    specified Azure subscription.
.DESCRIPTION
    If the StartVM parameter is set to True, then all virtual machines which are not in
    the power state 'VM running' are started. If the StartVM parameter is set to False,
    then virtual machines which are not in the power state 'VM deallocated' are stopped.
    
    If the $StartOrStopMode parameter is set Start, VMs which are not aldready running are started.
    If set to Stop, VMs which are not already deallocated are stopped.
#>

workflow StartOrStop-AllAzureRmVM
{
    param(
        [string]$AutomationPSCredentialName = "DefaultAzureCredential",
        [string]$SubscriptionId = "230e5e8e-a1a5-4ff2-a428-df4a621fb489",
        [Parameter(Mandatory=$true)]
        [ValidateSet("Start","Stop")] 
        [string]$StartOrStopMode,
        [string]$ResourceGroupName
    )
    
     function Get-AzureRmRunningVM([string]$ResourceGroupName, [string]$StartOrStopMode) {
        function Get-AzureRmVmPowerState($VM) {
            return Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status |
                   Select-Object -ExpandProperty Statuses |
                   Where-Object -FilterScript { $_.Code -match "PowerState" } |
                   Select-Object -ExpandProperty DisplayStatus
        }
    
        $vms = $null
        if ([string]::IsNullOrEmpty($ResourceGroupName)) {
            $vms = Get-AzureRmVM
        }
        else {
            $vms = Get-AzureRmVM -ResourceGroupName $ResourceGroupName
        }
        $vms | Where-Object -FilterScript {
            $actualState = Get-AzureRmVmPowerState $_
            $expectedState = "VM deallocated"
            if ($StartOrStopMode -eq "Start") {
                $expectedState = "VM running"
            }
            return $actualState -ne $expectedState
        }
    }

    function StartOrStop-AzureRmVM($vm, [string]$StartOrStopMode) {
        $stopRtn = $null
        if ($StartOrStopMode -eq "Start") {
            $stopRtn = $vm | Start-AzureRmVM -ErrorAction SilentlyContinue
        }
        else {
            $stopRtn = $vm | Stop-AzureRmVM -Force -ErrorAction SilentlyContinue
        }
        return $stopRtn
    }

    $cred = Get-AutomationPSCredential -Name $AutomationPSCredentialName

    # Connect to Azure (Login-AzureRmAccount works, but Select-AzureRmSubscription does not due to some dll-failure!)
    Add-AzureRmAccount -Credential $cred -SubscriptionId $SubscriptionId
    
    # Get all Azure VMs in the subscription that are running, and shut them down all at once.
    $vms = Get-AzureRmRunningVM -ResourceGroupName $ResourceGroupName -StartOrStopMode $StartOrStopMode
    $state = "not deallocated"
    if ($StartOrStopMode -eq "Start") {
        $state = "not running"
    }
    Write-Output "Found $(@($vms).length) $state VMs to process"
    
    foreach -parallel ($vm in $vms)
    {       
        $stopRtn = StartOrStop-AzureRmVM -vm $vm -StartOrStopMode $StartOrStopMode
        $count = 1
        if(($stopRtn.Status) -ne 'Succeeded') {
            do {
                Write-Output "Failed to $($StartOrStopMode.ToLower()) $($vm.Name). Retrying in 60 seconds... The reported error was: $($vm.Error)"
                sleep 60
                $stopRtn = StartOrStop-AzureRmVM -vm $vm -StartOrStopMode $StartOrStopMode
                $count++
            }
            while(($stopRtn.Status) -ne 'Succeeded' -and $count -lt 5)
        }
        if($stopRtn) {
            Write-Output "$StartOrStopMode-AzureRmVM cmdlet for $($vm.Name) $($stopRtn.Status.ToLower()) on attempt number $count of 5."
        }
    }
}
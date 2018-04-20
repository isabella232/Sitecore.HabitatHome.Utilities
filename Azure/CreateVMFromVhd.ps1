Param(
    [string] $subscriptionId,
    [ValidateSet('na', 'ga', 'emea')]
    [string]$region = 'na',
    [ValidateSet('xp', 'xc')]
    [string]$demoType,
    [string] $deploymentName = "habitathome"
)
$account = Get-AzureRMContext | Select-Object Account

if ($account.Account -eq $null) {
    Login-AzureRmAccount
}

#Provide the size of the virtual machine
#Get all the vm sizes in a region using below script:
#e.g. Get-AzureRmVMSize -Location eastus 
# available regions are "eastus", "australiaeast" and "ukwest"

$virtualMachineSize = 'Standard_DS12_V2_Promo'


#########       SHOULD not need to modify the following     #############

###########     Set up the source

switch ($region) {
    na {
        $storageAccountId = "/subscriptions/***REMOVED***/resourceGroups/habitathome-demo-snapshot/providers/Microsoft.Storage/storageAccounts/habitathomedemosnapshots"
        $storageContainerName = "habitathomedemosnapshots"
        $location = "eastus"
        $timeZone = "Eastern Standard Time"
    }
    ga {
        $storageAccountId = "/subscriptions/***REMOVED***/resourceGroups/habitathome-demo-snapshot-ga/providers/Microsoft.Storage/storageAccounts/hhdemosnapshotsga"
        $storageContainerName = "hhdemosnapshotsga"
        $location = "australiaeast"
        $timeZone = "E. Australia Standard Time"
    }
    emea {
        $storageAccountId = "/subscriptions/***REMOVED***/resourceGroups/habitathome-demo-snapshot-emea/providers/Microsoft.Storage/storageAccounts/hhdemosnapshotsemea"
        $storageContainerName = "hhdemosnapshotsemea"
        $location = "ukwest"
        $timeZone = "GMT Standard Time"
    }
}
$snapshotPrefix = ("habitathome{0}" -f $demoType)

#Provide the name of the snapshot that will be used to create OS disk
$osVHDUri = ("https://{0}.blob.core.windows.net/snapshots/{1}-os.vhd" -f $storageContainerName, $snapshotPrefix)
#Provide the name of the snapshot that will be used to create Data disk
$dataVHDUri = ("https://{0}.blob.core.windows.net/snapshots/{1}-data.vhd" -f $storageContainerName, $snapshotPrefix)

$resourceGroupName = $deploymentName

#Provide the name of the OS and data disks that will be created using the snapshot
$osDiskName = ("{0}_osDisk" -f $deploymentName.Replace("-", "_"))
$dataDiskName = ("{0}_data" -f $deploymentName.Replace("-", "_"))

#Provide the name of an existing virtual network where virtual machine will be created
$virtualNetworkName = ("{0}-vnet" -f $deploymentName)

#Provide the name of the virtual machine
$virtualMachineName = ("{0}-vm" -f $deploymentName)


Function Enable-AzureRMVmAutoShutdown {
    Param 
    (
        [Parameter(Mandatory = $true)] 
        [string] $SubscriptionId,
        [Parameter(Mandatory = $true)] 
        [string] $ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string] $VirtualMachineName,
        [int] $ShutdownTime = 2200,
        [string] $TimeZone = 'UTC'
    )
    Try {
        $Location = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName).Location
        $VMResourceId = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName).Id
        $ScheduledShutdownResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.devtestlab/schedules/shutdown-computevm-$VirtualMachineName"

        $Properties = @{}
        $Properties.Add('status', 'Enabled')
        $Properties.Add('taskType', 'ComputeVmShutdownTask')
        $Properties.Add('dailyRecurrence', @{'time' = $ShutdownTime})
        $Properties.Add('timeZoneId', $TimeZone)
        $Properties.Add('notificationSettings', @{status = 'Disabled'; timeInMinutes = 15})
        $Properties.Add('targetResourceId', $VMResourceId)
    
        New-AzureRmResource -Location $Location -ResourceId $ScheduledShutdownResourceId -Properties $Properties -Force
    }
    Catch {Write-Error $_}

}


#Set the context to the subscription Id where Managed Disks and VM will be created
Select-AzureRmSubscription -SubscriptionId $subscriptionId

New-AzureRmResourceGroup -Name $resourceGroupName -Location $location

# OS Disk
$osDisk = New-AzureRmDisk -DiskName $osDiskName -Disk `
(New-AzureRmDiskConfig -AccountType PremiumLRS  `
        -Location $location -CreateOption Import `
        -StorageAccountId $storageAccountId `
        -SourceUri $osVHDUri) `
    -ResourceGroupName $resourceGroupName

# Data Disk

$dataDisk = New-AzureRmDisk -DiskName $dataDiskName -Disk `
(New-AzureRmDiskConfig -AccountType PremiumLRS  `
        -Location $location -CreateOption Import `
        -StorageAccountId $storageAccountId `
        -SourceUri $dataVHDUri) `
    -ResourceGroupName $resourceGroupName

# Virtual Machine Configuraiton

#Initialize virtual machine configuration
$VirtualMachine = New-AzureRmVMConfig -VMName $virtualMachineName -VMSize $virtualMachineSize

#Use the Managed Disk Resource Id to attach it to the virtual machine. Please change the OS type to linux if OS disk has linux OS
$VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $osDisk.Id -CreateOption Attach -Windows
#Create a public IP for the VM
$publicIp = New-AzureRmPublicIpAddress -Name ("{0}_ip" -f $deploymentName) -ResourceGroupName $resourceGroupName -Location $location -AllocationMethod Static

#Get the virtual network where virtual machine will be hosted
$vnet = New-AzureRmVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix 10.0.0.0/24
Add-AzureRmVirtualNetworkSubnetConfig -Name sNet -VirtualNetwork $vnet -AddressPrefix 10.0.0.0/24
$vnet | Set-AzureRmVirtualNetwork

# set up network security rules and group
$http = New-AzureRmNetworkSecurityRuleConfig  -Name "HTTP" -Description "Allow inbound HTTP" -Protocol Tcp -SourcePortRange * -DestinationPortRange 80 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 101 -Direction Inbound 
$https = New-AzureRmNetworkSecurityRuleConfig -Name "HTTPS" -Description "Allow inbound HTTPS" -Protocol Tcp -SourcePortRange * -DestinationPortRange 443 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 105 -Direction Inbound 
$commerce = New-AzureRmNetworkSecurityRuleConfig -Name "Commerce" -Description "Allow Commerce Ports" -Protocol Tcp -SourcePortRange * -DestinationPortRange 5000-5100 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 110 -Direction Inbound
$idserver = New-AzureRmNetworkSecurityRuleConfig -Name "IdentityServer" -Description "Allow Identity Server Ports" -Protocol Tcp -SourcePortRange * -DestinationPortRange 4200 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 120 -Direction Inbound
$rdp = New-AzureRmNetworkSecurityRuleConfig -Name "rdp" -Description "Allow RDP" -Protocol Tcp -SourcePortRange * -DestinationPortRange 3389 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 1000 -Direction Inbound

$smtpOutbound = New-AzureRmNetworkSecurityRuleConfig -Name "SMTP" -Description "Allow SMTP" -Protocol Tcp -SourcePortRange * -DestinationPortRange 25 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 1140 -Direction Outbound 

$networkSecurityGroupName = ("{0}-nsg" -f $deploymentName)

if ($demoType -eq "xc") {
    # Only open ports 50xx and 4200 for an XC demo 
    $nsg = New-AzureRmNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName  -Location  $location `
        -SecurityRules $http, $https, $commerce, $idserver, $rdp, $smtpOutbound
}
else {
    $nsg = New-AzureRmNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName  -Location  $location `
        -SecurityRules $http, $https, $rdp, $smtpOutbound
}

$vnet = Get-AzureRmVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName

# Create NIC in the first subnet of the virtual network
$nic = New-AzureRmNetworkInterface -Name ("{0}_nic" -f $deploymentName.Replace("-", "_"))  -ResourceGroupName $resourceGroupName -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $publicIp.Id -NetworkSecurityGroupId $nsg.Id

$VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $nic.Id

#Create the virtual machine with Managed Disk
New-AzureRmVM -VM $VirtualMachine -ResourceGroupName $resourceGroupName -Location $location
$vm = Get-AzureRmVM -Name $virtualMachineName -ResourceGroupName $resourceGroupName
$vm = Add-AzureRmVMDataDisk -VM $vm -Name $dataDiskName -CreateOption Attach -ManagedDiskId $dataDisk.id -Lun 1

Update-AzureRmVM -VM $vm -ResourceGroupName $resourceGroupName

Enable-AzureRMVmAutoShutdown -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -VirtualMachineName $virtualMachineName -TimeZone $timeZone
#Requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^rg-lab6-[0-9]+-cli$')]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$Location,

    [Parameter(Mandatory)]
    [string]$PublicKeyPath,

    [ValidateSet('Standard_B1s', 'Standard_B2ats_v2')]
    [string]$VmSize = 'Standard_B2ats_v2'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ([string]::IsNullOrWhiteSpace($env:ARM_SUBSCRIPTION_ID)) {
    throw 'Ustaw ARM_SUBSCRIPTION_ID na identyfikator subskrypcji labu.'
}

if (-not (Test-Path -LiteralPath $PublicKeyPath -PathType Leaf)) {
    throw "Brak pliku klucza publicznego: $PublicKeyPath"
}

$publicKey = (Get-Item -LiteralPath $PublicKeyPath).FullName
$vm = 'lab6-vm'
$extension = 'lab6-bootstrap'
$bootstrap = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'bootstrap.sh'))

function Invoke-LabAz {
    az @args --subscription $env:ARM_SUBSCRIPTION_ID
}

$groupExists = Invoke-LabAz group exists --name $ResourceGroupName --output tsv
if ($groupExists -ne 'false') {
    throw "Wybierz nową grupę zasobów. Grupa $ResourceGroupName już istnieje."
}

Write-Host '1. Grupa zasobów i sieć'
Invoke-LabAz group create --name $ResourceGroupName --location $Location --output none
Invoke-LabAz network vnet create --resource-group $ResourceGroupName --location $Location `
    --name lab6-vnet --address-prefixes 10.60.0.0/16 --output none
Invoke-LabAz network nsg create --resource-group $ResourceGroupName --location $Location `
    --name lab6-nsg --output none
$subnetId = Invoke-LabAz network vnet subnet create --resource-group $ResourceGroupName `
    --vnet-name lab6-vnet --name app --address-prefixes 10.60.1.0/24 `
    --default-outbound-access true --network-security-group lab6-nsg --query id --output tsv

Write-Host '2. Interfejs VM w podsieci z domyślnym wyjściem do Internetu'
Invoke-LabAz network nic create --resource-group $ResourceGroupName --location $Location `
    --name lab6-nic --subnet $subnetId --output none
$nicId = Invoke-LabAz network nic show --resource-group $ResourceGroupName --name lab6-nic `
    --query id --output tsv

Write-Host '3. Zlecenie utworzenia VM i oczekiwanie na stan Succeeded'
Invoke-LabAz vm create --resource-group $ResourceGroupName --location $Location --name $vm `
    --nics $nicId --size $VmSize --os-disk-size-gb 64 --storage-sku Premium_LRS `
    --image Canonical:ubuntu-24_04-lts:server-gen1:latest `
    --admin-username labuser --authentication-type ssh --ssh-key-values $publicKey `
    --no-wait --output none
Invoke-LabAz vm wait --resource-group $ResourceGroupName --name $vm `
    --created --interval 10 --timeout 900 --output none

Write-Host '4. Zlecenie instalacji Dockera i oczekiwanie na zakończenie rozszerzenia'
$settingsFile = New-TemporaryFile
try {
    @{ script = [Convert]::ToBase64String($bootstrap) } |
        ConvertTo-Json -Compress |
        Set-Content -LiteralPath $settingsFile.FullName -Encoding utf8NoBOM

    Invoke-LabAz vm extension set --resource-group $ResourceGroupName --vm-name $vm `
        --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 `
        --extension-instance-name $extension --protected-settings $settingsFile.FullName `
        --no-wait --output none
}
finally {
    Remove-Item -LiteralPath $settingsFile.FullName
}

Invoke-LabAz vm extension wait --resource-group $ResourceGroupName --vm-name $vm --name $extension `
    --created --interval 10 --timeout 900 --output none

Write-Host '5. Niezależny test HTTP wewnątrz VM'
$response = Invoke-LabAz vm run-command invoke --resource-group $ResourceGroupName --name $vm `
    --command-id RunShellScript --scripts 'curl -fsS http://127.0.0.1:8080/' `
    --query 'value[].message' --output tsv
$response
if (($response -join [Environment]::NewLine) -notlike '*Lab 6: Nginx na Azure VM*') {
    throw 'Nginx nie zwrócił oczekiwanej strony.'
}

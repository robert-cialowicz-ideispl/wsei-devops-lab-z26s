[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$ClusterName,

    [Parameter(Mandatory)]
    [string]$VmSize,

    [string[]]$Regions
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Brak polecenia az. Uruchom skrypt w Azure Cloud Shell w trybie PowerShell.'
}

function Invoke-LabAz([string[]]$CliArguments) {
    $output = & az @CliArguments
    if ($LASTEXITCODE -ne 0) {
        $command = $CliArguments[0..1] -join ' '
        throw "Polecenie az $command zakończyło się kodem $LASTEXITCODE."
    }
    $output
}

function Invoke-LabAzJson([string[]]$CliArguments) {
    $lines = Invoke-LabAz $CliArguments
    ConvertFrom-Json -InputObject ($lines -join "`n") -NoEnumerate
}

function Find-LabSku([string]$Region) {
    $url = "$armEndpoint/subscriptions/$subscription/providers/Microsoft.Compute/skus?api-version=2021-07-01&%24filter=location%20eq%20%27$Region%27"
    while ($url) {
        $page = Invoke-LabAzJson @('rest', '--method', 'get', '--url', $url, '--only-show-errors', '--output', 'json')
        $sku = $page.value | Where-Object {
            $_.resourceType -eq 'virtualMachines' -and $_.name -eq $VmSize -and $_.locations -contains $Region
        } | Select-Object -First 1
        if ($sku) { return $sku }
        $url = $page.nextLink
    }
}

function Test-LabQuota {
    param([object[]]$Usage, [string]$Name, [int]$Needed, [switch]$Required)

    $meter = $Usage | Where-Object { $_.name.value -eq $Name } | Select-Object -First 1
    $limit = 0L
    $used = 0L
    if (-not $meter -or -not [long]::TryParse([string]$meter.limit, [ref]$limit) -or
        ($limit -ge 0 -and -not [long]::TryParse([string]$meter.currentValue, [ref]$used))) {
        Write-Host "  Brak danych o limicie $Name."
        return -not $Required
    }

    $remaining = $limit - $used
    if ($limit -lt 0 -or $remaining -ge $Needed) { return $true }
    Write-Host "  Limit $Name ma $remaining wolnych jednostek. Potrzeba $Needed."
    return $false
}

$subscription = Invoke-LabAz @('account', 'show', '--query', 'id', '--output', 'tsv')
if (-not $subscription) { throw 'Wybierz aktywną subskrypcję Azure.' }
$armEndpoint = (Invoke-LabAz @('cloud', 'show', '--query', 'endpoints.resourceManager', '--output', 'tsv')).TrimEnd('/')
$groupExists = (Invoke-LabAz @('group', 'exists', '--name', $ResourceGroupName, '--subscription', $subscription, '--output', 'tsv')) -eq 'true'

$existingRegion = $null
if ($groupExists) {
    $existingRegion = Invoke-LabAz @('group', 'show', '--name', $ResourceGroupName, '--subscription', $subscription, '--query', 'location', '--output', 'tsv')
    Write-Host "Istniejąca grupa $ResourceGroupName jest w regionie $existingRegion."
    if (-not $Regions) { $Regions = @($existingRegion) }
}

if (-not $Regions) {
    $locations = Invoke-LabAzJson @('account', 'list-locations', '--output', 'json')
    $Regions = @($locations |
        Where-Object { $_.metadata.regionType -eq 'Physical' } |
        Sort-Object @{ Expression = { $_.metadata.geographyGroup -ne 'Europe' } }, name |
        ForEach-Object { $_.name })
    if (-not $Regions) { throw 'Subskrypcja nie zwróciła żadnego regionu.' }
}

$templatePath = Join-Path ([IO.Path]::GetTempPath()) "lab7-preflight-$([guid]::NewGuid().ToString('N')).json"
$groupId = "/subscriptions/$subscription/resourceGroups/$ResourceGroupName"
$clusterId = "$groupId/providers/Microsoft.ContainerService/managedClusters/$ClusterName"

try {
    $preflight = Join-Path $PSScriptRoot 'preflight.bicep'
    Invoke-LabAz @('bicep', 'build', '--file', $preflight, '--stdout', '--only-show-errors') |
        Set-Content -LiteralPath $templatePath -Encoding utf8
    $template = Get-Content -Raw -LiteralPath $templatePath | ConvertFrom-Json
    $cluster = $template.resources | Where-Object type -eq 'Microsoft.Resources/deployments' |
        ForEach-Object { $_.properties.template.resources } |
        Where-Object type -eq 'Microsoft.ContainerService/managedClusters' | Select-Object -First 1
    $pool = $cluster.properties.agentPoolProfiles | Where-Object mode -eq 'System' | Select-Object -First 1
    if (-not $pool -or $pool.count -lt 1) { throw 'Brak początkowej liczby węzłów w szablonie AKS.' }

    # Ćwiczenie ze skalowaniem dodaje jeden węzeł do początkowej puli.
    $peakNodeCount = [int]$pool.count + 1

    foreach ($candidate in $Regions) {
        $region = $candidate.ToLowerInvariant()
        if ($region -notmatch '^[a-z0-9]+$') {
            Write-Host "Pomijam nieprawidłową nazwę regionu $candidate."
            continue
        }
        if ($groupExists -and $region -ne $existingRegion) { continue }

        Write-Host "Sprawdzam $region ($VmSize)."
        try {
            $versions = Invoke-LabAzJson @('aks', 'get-versions', '--location', $region, '--subscription', $subscription, '--output', 'json')
            if (-not $versions.values) {
                Write-Host '  Azure nie zwrócił obsługiwanych wersji AKS dla tego regionu.'
                continue
            }

            $sku = Find-LabSku $region
            if (-not $sku -or ($sku.restrictions | Where-Object type -eq 'Location')) {
                Write-Host '  Azure nie potwierdził dostępności tego rozmiaru VM.'
                continue
            }
            $vcpus = ($sku.capabilities | Where-Object name -eq 'vCPUs' | Select-Object -First 1).value
            if (-not $sku.family -or [int]$vcpus -lt 1) {
                Write-Host '  Brak informacji o rodzinie VM albo liczbie vCPU.'
                continue
            }

            $neededVcpus = $peakNodeCount * [int]$vcpus
            $compute = Invoke-LabAzJson @('vm', 'list-usage', '--location', $region, '--subscription', $subscription, '--output', 'json')
            if (-not (Test-LabQuota $compute 'cores' $neededVcpus -Required) -or
                -not (Test-LabQuota $compute $sku.family $neededVcpus -Required) -or
                -not (Test-LabQuota $compute 'virtualMachines' $peakNodeCount) -or
                -not (Test-LabQuota $compute 'virtualMachineScaleSets' 1)) { continue }

            $network = Invoke-LabAzJson @('network', 'list-usages', '--location', $region, '--subscription', $subscription, '--output', 'json')
            if (-not (Test-LabQuota $network 'VirtualNetworks' 1) -or
                -not (Test-LabQuota $network 'NetworkSecurityGroups' 1) -or
                -not (Test-LabQuota $network 'NetworkInterfaces' $peakNodeCount) -or
                -not (Test-LabQuota $network 'StandardSkuLoadBalancers' 1) -or
                -not (Test-LabQuota $network 'IPv4StandardSkuPublicIpAddresses' 1)) { continue }

            Write-Host '  Azure Resource Manager sprawdza wdrożenie i zastosowanie zasad.'
            $plan = Invoke-LabAzJson @(
                'deployment', 'sub', 'what-if', '--subscription', $subscription, '--location', $region,
                '--name', "lab7-preflight-$([guid]::NewGuid().ToString('N'))", '--template-file', $templatePath,
                '--parameters', "groupName=$ResourceGroupName", "clusterName=$ClusterName", "location=$region", "vmSize=$VmSize",
                '--validation-level', 'Provider', '--result-format', 'ResourceIdOnly', '--no-pretty-print', '--only-show-errors', '--output', 'json'
            )
            $createdIds = $plan.changes | Where-Object changeType -eq 'Create' | ForEach-Object { $_.resourceId }
            if ($plan.status -ne 'Succeeded' -or (-not $groupExists -and $groupId -notin $createdIds) -or $clusterId -notin $createdIds) {
                Write-Host '  Plan nie potwierdził utworzenia wszystkich wymaganych zasobów.'
                continue
            }

            return $region
        } catch {
            Write-Host "  $($_.Exception.Message)"
        }
    }

    throw 'Żaden sprawdzony region nie przeszedł weryfikacji.'
} finally {
    Remove-Item -LiteralPath $templatePath -ErrorAction SilentlyContinue
}

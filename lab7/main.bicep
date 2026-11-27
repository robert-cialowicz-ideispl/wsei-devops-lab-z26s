targetScope = 'resourceGroup'

param clusterName string
param vmSize string = 'Standard_D2als_v6'
param location string = resourceGroup().location

resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: location
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: subscription().tenantId
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        count: 2
        vmSize: vmSize
        maxPods: 30
        osDiskSizeGB: 64
        osDiskType: 'Managed'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
  }
}

targetScope = 'subscription'

param groupName string
param clusterName string
param location string
param vmSize string

resource labGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: groupName
  location: location
}

module aks 'main.bicep' = {
  name: 'lab7-aks-preflight'
  scope: labGroup
  params: {
    clusterName: clusterName
    location: location
    vmSize: vmSize
  }
}

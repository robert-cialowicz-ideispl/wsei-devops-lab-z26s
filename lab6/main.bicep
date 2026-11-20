targetScope = 'resourceGroup'

@allowed([
  'Standard_B1s'
  'Standard_B2ats_v2'
])
param vmSize string

param sshPublicKey string
param adminUsername string = 'labuser'

var location = resourceGroup().location

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'lab6-nsg'
  location: location
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'lab6-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.60.0.0/16']
    }
    subnets: [
      {
        name: 'app'
        properties: {
          addressPrefix: '10.60.1.0/24'
          defaultOutboundAccess: true
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: 'lab6-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'app'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'lab6-vm'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'lab6-vm'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server-gen1'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        diskSizeGB: 64
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
  }
}

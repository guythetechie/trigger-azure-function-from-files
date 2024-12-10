targetScope = 'subscription'

var location = 'eastus'
var prefix = 'func-from-file'
var subscriptionScopePrefix = '${prefix}-${take(uniqueString(subscription().id), 6)}'
var resourceGroupName = '${subscriptionScopePrefix}-rg'
var resourceGroupScopePrefix = '${prefix}-${take(uniqueString(subscription().id, resourceGroupName), 6)}'
var virtualNetworkName = '${resourceGroupScopePrefix}-vnet'
var privateLinkSubnetName = 'private-link'
var eventHubNamespaceName = '${resourceGroupScopePrefix}-ehns'
var storageAccountName = replace('${resourceGroupScopePrefix}stor', '-', '')
var fileShareName = 'uploads'

module resourceGroupDeployment 'br/public:avm/res/resources/resource-group:0.4.0' = {
  name: 'resource-group-deployment'
  params: {
    name: resourceGroupName
    location: location
  }
}

module virtualNetworkDeployment 'br/public:avm/res/network/virtual-network:0.5.1' = {
  scope: resourceGroup(resourceGroupName)
  dependsOn: [resourceGroupDeployment]
  name: 'virtual-network-deployment'
  params: {
    name: virtualNetworkName
    addressPrefixes: ['10.0.0.0/24']
    location: location
    subnets: [
      {
        name: privateLinkSubnetName
        addressPrefix: '10.0.0.0/28'
      }
    ]
  }
}

module eventHubNamespaceDeployment 'br/public:avm/res/event-hub/namespace:0.7.1' = {
  scope: resourceGroup(resourceGroupName)
  dependsOn: [resourceGroupDeployment]
  name: 'event-hub-namespace-deployment'
  params: {
    location: location
    name: eventHubNamespaceName
    skuName: 'Basic'
  }
}

module storagePrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.6.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'storage-private-dns-zone-deployment'
  params: {
    name: 'privatelink.file.${environment().suffixes.storage}'
    location: 'global'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkDeployment.outputs.resourceId
      }
    ]
  }
}

module storageAccountDeployment 'br/public:avm/res/storage/storage-account:0.14.3' = {
  scope: resourceGroup(resourceGroupName)
  name: 'storage-account-deployment'
  params: {
    name: storageAccountName
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    fileServices: {
      shares: [
        {
          name: fileShareName
        }
      ]
    }
    publicNetworkAccess: 'Disabled'
    privateEndpoints: [
      {
        name: '${storageAccountName}-pep'
        customNetworkInterfaceName: '${storageAccountName}-nic'
        service: 'file'
        subnetResourceId: virtualNetworkDeployment.outputs.subnetResourceIds[0]
        privateDnsZoneGroup: {
          name: storageAccountName
          privateDnsZoneGroupConfigs: [
            {
              name: storagePrivateDnsZone.outputs.name
              privateDnsZoneResourceId: storagePrivateDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
  }
}

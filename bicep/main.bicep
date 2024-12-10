targetScope = 'subscription'

var location = 'eastus'
var prefix = 'func-from-file'
var subscriptionScopePrefix = '${prefix}-${take(uniqueString(subscription().id), 6)}'
var resourceGroupName = '${subscriptionScopePrefix}-rg'
var resourceGroupScopePrefix = '${prefix}-${take(uniqueString(subscription().id, resourceGroupName), 6)}'
var virtualNetworkName = '${resourceGroupScopePrefix}-vnet'
var privateLinkSubnetName = 'private-link'
var eventHubNamespaceName = '${resourceGroupScopePrefix}-ehns'
var azureMonitorEventHubAuthorizationRuleName = 'AzureMonitor'
var storageLogsEventHubName = '${storageAccountName}-files'
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

module serviceBusPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.6.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'service-bus-private-dns-zone-deployment'
  dependsOn: [resourceGroupDeployment]
  params: {
    name: 'privatelink.servicebus.windows.net'
    location: 'global'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkDeployment.outputs.resourceId
      }
    ]
  }
}

module eventHubNamespaceDeployment 'br/public:avm/res/event-hub/namespace:0.7.1' = {
  scope: resourceGroup(resourceGroupName)
  name: 'event-hub-namespace-deployment'
  params: {
    location: location
    name: eventHubNamespaceName
    skuName: 'Standard'
    authorizationRules: [
      {
        name: azureMonitorEventHubAuthorizationRuleName
        rights: [
          'Listen'
          'Manage'
          'Send'
        ]
      }
    ]
    eventhubs: [
      {
        name: storageLogsEventHubName
        partitionCount: 1
      }
    ]
    disableLocalAuth: false
    publicNetworkAccess: 'Disabled'
    networkRuleSets: {
      name: 'default'
      defaultAction: 'Deny'
      publicNetworkAccess: 'Disabled'
      trustedServiceAccessEnabled: true
    }
    privateEndpoints: [
      {
        name: '${eventHubNamespaceName}-pep'
        customNetworkInterfaceName: '${eventHubNamespaceName}-nic'
        service: 'namespace'
        subnetResourceId: virtualNetworkDeployment.outputs.subnetResourceIds[0]
        privateDnsZoneGroup: {
          name: eventHubNamespaceName
          privateDnsZoneGroupConfigs: [
            {
              // Event hub uses the same private DNS zone as service bus
              name: serviceBusPrivateDnsZone.outputs.name
              privateDnsZoneResourceId: serviceBusPrivateDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
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
      diagnosticSettings: [
        {
          name: 'send-storage-write-to-event-hub'
          logCategoriesAndGroups: [
            {
              category: 'StorageWrite'
            }
          ]
          eventHubAuthorizationRuleResourceId: '${eventHubNamespaceDeployment.outputs.resourceId}/authorizationrules/${azureMonitorEventHubAuthorizationRuleName}'
          eventHubName: storageLogsEventHubName
        }
      ]
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

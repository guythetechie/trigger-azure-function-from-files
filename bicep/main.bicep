targetScope = 'subscription'

var location = 'eastus'
var prefix = 'trigger-from-file'
var subscriptionScopePrefix = '${prefix}-${take(uniqueString(subscription().id), 4)}'
var resourceGroupName = '${subscriptionScopePrefix}-rg'
var resourceGroupScopePrefix = '${prefix}-${take(uniqueString(subscription().id, resourceGroupName), 4)}'
var logAnalyticsWorkspaceName = '${resourceGroupScopePrefix}-law'
var applicationInsightsName = '${resourceGroupScopePrefix}-app-insights'
var virtualNetworkName = '${resourceGroupScopePrefix}-vnet'
var privateLinkSubnetName = 'private-link'
var vnetIntegrationSubnetName = 'vnet-integration'
var eventHubNamespaceName = '${resourceGroupScopePrefix}-ehns'
var azureMonitorEventHubAuthorizationRuleName = 'AzureMonitor'
var storageLogsEventHubName = '${storageAccountName}-files'
var storageAccountName = replace('${resourceGroupScopePrefix}stor', '-', '')
var functionAppContainerName = 'function-app'
var fileShareName = 'uploads'
var functionAppName = '${resourceGroupScopePrefix}-func'
var appServicePlanName = '${functionAppName}-plan'

var privateLinkSubnetResourceId = '${virtualNetworkDeployment.outputs.resourceId}/subnets/${privateLinkSubnetName}'
var vnetIntegrationSubnetResourceId = '${virtualNetworkDeployment.outputs.resourceId}/subnets/${vnetIntegrationSubnetName}'
var serviceBusDomainName = 'servicebus.windows.net'

module resourceGroupDeployment 'br/public:avm/res/resources/resource-group:0.4.0' = {
  name: 'resource-group-deployment'
  params: {
    name: resourceGroupName
    location: location
  }
}

resource storageBlobDataOwnerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  scope: subscription()
}

resource storageFileDataPrivilegedReader 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: 'b8eda974-7b85-4f76-af95-65846b26df6d'
  scope: subscription()
}

resource eventHubDataReceiverRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde'
  scope: subscription()
}

module logAnalyticsWorkspaceDeployment 'br/public:avm/res/operational-insights/workspace:0.9.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'log-analytics-workspace-deployment'
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
  }
}

module applicationInsightsDeployment 'br/public:avm/res/insights/component:0.3.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'application-insights-deployment'
  params: {
    name: applicationInsightsName
    location: location
    workspaceResourceId: logAnalyticsWorkspaceDeployment.outputs.resourceId
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
      {
        name: vnetIntegrationSubnetName
        addressPrefix: '10.0.0.64/26'
        delegation: 'Microsoft.App/environments'
      }
    ]
  }
}

module serviceBusPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.6.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'service-bus-private-dns-zone-deployment'
  dependsOn: [resourceGroupDeployment]
  params: {
    name: 'privatelink.${serviceBusDomainName}'
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
      trustedServiceAccessEnabled: true
    }
    privateEndpoints: [
      {
        name: '${eventHubNamespaceName}-pep'
        customNetworkInterfaceName: '${eventHubNamespaceName}-nic'
        service: 'namespace'
        subnetResourceId: privateLinkSubnetResourceId
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

module storageBlobPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.6.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'storage-blob-private-dns-zone-deployment'
  params: {
    name: 'privatelink.blob.${environment().suffixes.storage}'
    location: 'global'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkDeployment.outputs.resourceId
      }
    ]
  }
}

module storageFilePrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.6.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'storage-file-private-dns-zone-deployment'
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
    blobServices: {
      containers: [
        {
          name: functionAppContainerName
          publicAccess: 'None'
        }
      ]
      diagnosticSettings: [
        {
          name: 'enable-all'
          logAnalyticsDestinationType: 'Dedicated'
          metricCategories: []
          logCategoriesAndGroups: [
            {
              categoryGroup: 'AllLogs'
            }
          ]
          workspaceResourceId: logAnalyticsWorkspaceDeployment.outputs.resourceId
        }
      ]
    }
    fileServices: {
      diagnosticSettings: [
        {
          name: 'send-storage-write-to-event-hub'
          metricCategories: []
          logCategoriesAndGroups: [
            {
              category: 'StorageWrite'
            }
          ]
          eventHubAuthorizationRuleResourceId: '${eventHubNamespaceDeployment.outputs.resourceId}/authorizationrules/${azureMonitorEventHubAuthorizationRuleName}'
          eventHubName: storageLogsEventHubName
        }
        {
          name: 'enable-all'
          logAnalyticsDestinationType: 'Dedicated'
          metricCategories: []
          logCategoriesAndGroups: [
            {
              categoryGroup: 'AllLogs'
            }
          ]
          workspaceResourceId: logAnalyticsWorkspaceDeployment.outputs.resourceId
        }
      ]
      shares: [
        {
          name: fileShareName
        }
      ]
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    privateEndpoints: [
      {
        name: '${storageAccountName}-blob-pep'
        customNetworkInterfaceName: '${storageAccountName}-blob-nic'
        service: 'blob'
        subnetResourceId: privateLinkSubnetResourceId
        privateDnsZoneGroup: {
          name: storageAccountName
          privateDnsZoneGroupConfigs: [
            {
              name: storageBlobPrivateDnsZone.outputs.name
              privateDnsZoneResourceId: storageBlobPrivateDnsZone.outputs.resourceId
            }
          ]
        }
      }
      {
        name: '${storageAccountName}-file-pep'
        customNetworkInterfaceName: '${storageAccountName}-file-nic'
        service: 'file'
        subnetResourceId: privateLinkSubnetResourceId
        privateDnsZoneGroup: {
          name: storageAccountName
          privateDnsZoneGroupConfigs: [
            {
              name: storageFilePrivateDnsZone.outputs.name
              privateDnsZoneResourceId: storageFilePrivateDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
  }
}

module appServicePlanDeployment 'br/public:avm/res/web/serverfarm:0.3.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'app-service-plan-deployment'
  params: {
    name: appServicePlanName
    location: location
    kind: 'FunctionApp'
    skuName: 'FC1'
    reserved: true
  }
}

module functionAppDeployment 'br/public:avm/res/web/site:0.10.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'function-app-deployment'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    managedIdentities: {
      systemAssigned: true
    }
    serverFarmResourceId: appServicePlanDeployment.outputs.resourceId
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storageAccountDeployment.outputs.serviceEndpoints.blob
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: storageAccountDeployment.outputs.serviceEndpoints.queue
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: storageAccountDeployment.outputs.serviceEndpoints.table
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsDeployment.outputs.connectionString
        }
        {
          name: 'EVENT_HUB_NAME'
          value: storageLogsEventHubName
        }
        {
          name: 'EVENT_HUB_CONNECTION__fullyQualifiedNamespace'
          value: '${eventHubNamespaceDeployment.outputs.name}.${serviceBusDomainName}'
        }
        {
          name: 'EVENT_HUB_CONNECTION__credential'
          value: 'managedidentity'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    vnetRouteAllEnabled: false
    vnetContentShareEnabled: true
    vnetImagePullEnabled: true
    virtualNetworkSubnetId: vnetIntegrationSubnetResourceId
    functionAppConfig: {
      use32BitWorkerProcess: false
      deployment: {
        storage: {
          type: 'blobContainer'
          value: uri(storageAccountDeployment.outputs.primaryBlobEndpoint, functionAppContainerName)
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '9.0'
      }
    }
  }
}

module functionStorageAccountBlobRoleAssignemnt 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  scope: resourceGroup(resourceGroupName)
  name: 'function-app-storage-account-blob-role-assignment-deployment'
  params: {
    principalId: functionAppDeployment.outputs.systemAssignedMIPrincipalId
    resourceId: storageAccountDeployment.outputs.resourceId
    roleDefinitionId: storageBlobDataOwnerRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}

module functionStorageAccountFileRoleAssignemnt 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  scope: resourceGroup(resourceGroupName)
  name: 'function-app-storage-account-file-role-assignment-deployment'
  params: {
    principalId: functionAppDeployment.outputs.systemAssignedMIPrincipalId
    resourceId: '${storageAccountDeployment.outputs.resourceId}/fileServices/default/fileshares/${fileShareName}'
    roleDefinitionId: storageFileDataPrivilegedReader.id
    principalType: 'ServicePrincipal'
  }
}

module functionAppEventHubRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  scope: resourceGroup(resourceGroupName)
  name: 'function-app-event-hub-role-assignment-deployment'
  params: {
    principalId: functionAppDeployment.outputs.systemAssignedMIPrincipalId
    resourceId: '${eventHubNamespaceDeployment.outputs.resourceId}/eventhubs/${storageLogsEventHubName}'
    roleDefinitionId: eventHubDataReceiverRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}

output resourceGroupName string = resourceGroupName
output functionAppName string = functionAppName

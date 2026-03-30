// Self-Healing AKS Cluster - Main Infrastructure
// Deploys: AKS + Log Analytics + Container Insights

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region')
param location string = resourceGroup().location

@description('AKS node count')
@minValue(1)
@maxValue(10)
param nodeCount int = 2

@description('AKS node VM size')
param nodeVmSize string = 'Standard_D2s_v3'

// Variables
var suffix = uniqueString(resourceGroup().id)
var aksName = 'aks-selfheal-${environment}'
var logAnalyticsName = 'log-selfheal-${environment}-${suffix}'
var vnetName = 'vnet-selfheal-${environment}'

// Tags
var tags = {
  Environment: environment
  Project: 'Self-Healing-AKS'
  ManagedBy: 'Bicep'
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

// AKS Cluster
resource aks 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: aksName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    kubernetesVersion: '1.28'
    enableRBAC: true
    
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: vnet.properties.subnets[0].id
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        // Enable auto-repair
        enableNodePublicIP: false
      }
    ]
    
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
    }
    
    // Container Insights
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
      azurepolicy: {
        enabled: true
      }
    }
    
    // Auto-upgrade
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }
  }
}

// Outputs
output aksName string = aks.name
output aksId string = aks.id
output kubeletIdentity string = aks.properties.identityProfile.kubeletidentity.objectId
output logAnalyticsId string = logAnalytics.id


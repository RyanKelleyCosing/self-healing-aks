// Self-Healing Logic App - Auto-remediation
// Receives alerts from Prometheus AlertManager and triggers remediation

@description('Environment name')
param environment string = 'dev'

@description('Azure region')
param location string = resourceGroup().location

@description('AKS cluster name')
param aksClusterName string

@description('AKS resource group')
param aksResourceGroup string = resourceGroup().name

// Variables
var suffix = uniqueString(resourceGroup().id)
var logicAppName = 'logic-selfheal-${environment}-${suffix}'

// Tags
var tags = {
  Environment: environment
  Project: 'Self-Healing-AKS'
  ManagedBy: 'Bicep'
}

// Logic App
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                alerts: {
                  type: 'array'
                  items: {
                    type: 'object'
                    properties: {
                      status: { type: 'string' }
                      labels: { type: 'object' }
                      annotations: { type: 'object' }
                    }
                  }
                }
              }
            }
          }
        }
      }
      actions: {
        Parse_Alert: {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              type: 'object'
              properties: {
                alerts: { type: 'array' }
              }
            }
          }
          runAfter: {}
        }
        For_Each_Alert: {
          type: 'Foreach'
          foreach: '@body(\'Parse_Alert\')?[\'alerts\']'
          actions: {
            Check_Alert_Type: {
              type: 'Switch'
              expression: '@items(\'For_Each_Alert\')?[\'labels\']?[\'alertname\']'
              cases: {
                PodCrashLooping: {
                  case: 'PodCrashLooping'
                  actions: {
                    Restart_Pod: {
                      type: 'Http'
                      inputs: {
                        method: 'DELETE'
                        uri: 'https://management.azure.com/subscriptions/@{subscription().subscriptionId}/resourceGroups/${aksResourceGroup}/providers/Microsoft.ContainerService/managedClusters/${aksClusterName}/runCommand?api-version=2024-01-01'
                        body: {
                          command: 'kubectl delete pod @{items(\'For_Each_Alert\')?[\'labels\']?[\'pod\']} -n @{items(\'For_Each_Alert\')?[\'labels\']?[\'namespace\']}'
                        }
                        authentication: {
                          type: 'ManagedServiceIdentity'
                        }
                      }
                    }
                  }
                }
                HighMemoryUsage: {
                  case: 'HighMemoryUsage'
                  actions: {
                    Scale_Deployment: {
                      type: 'Http'
                      inputs: {
                        method: 'POST'
                        uri: 'https://management.azure.com/subscriptions/@{subscription().subscriptionId}/resourceGroups/${aksResourceGroup}/providers/Microsoft.ContainerService/managedClusters/${aksClusterName}/runCommand?api-version=2024-01-01'
                        body: {
                          command: 'kubectl scale deployment @{items(\'For_Each_Alert\')?[\'labels\']?[\'deployment\']} --replicas=@{add(int(items(\'For_Each_Alert\')?[\'labels\']?[\'replicas\']), 1)} -n @{items(\'For_Each_Alert\')?[\'labels\']?[\'namespace\']}'
                        }
                        authentication: {
                          type: 'ManagedServiceIdentity'
                        }
                      }
                    }
                  }
                }
              }
              default: {
                actions: {
                  Log_Unknown_Alert: {
                    type: 'Compose'
                    inputs: 'Unknown alert type: @{items(\'For_Each_Alert\')?[\'labels\']?[\'alertname\']}'
                  }
                }
              }
            }
          }
          runAfter: {
            Parse_Alert: ['Succeeded']
          }
        }
      }
    }
  }
}

// Role assignment for AKS access
resource aksContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicApp.id, 'AKS-Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output logicAppName string = logicApp.name
output webhookUrl string = listCallbackUrl('${logicApp.id}/triggers/manual', '2019-05-01').value


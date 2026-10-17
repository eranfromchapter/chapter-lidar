// Role assignments on the shared registry (deployed into the registry's resource group).
// api and worker identities: AcrPull. GitHub deploy identity: AcrPush.

@description('Registry name.')
param registryName string

@description('API container app name (used for stable role assignment names).')
param apiAppName string

@description('Worker container app name (used for stable role assignment names).')
param workerAppName string

@description('Deploy identity name (used for stable role assignment names).')
param deployIdentityName string

@description('Principal ID of the API system-assigned identity.')
param apiPrincipalId string

@description('Principal ID of the worker system-assigned identity.')
param workerPrincipalId string

@description('Principal ID of the GitHub deploy identity.')
param deployPrincipalId string

var acrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var acrPush = '8311e382-0749-4cb8-b61a-304f252e45ec'

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource apiPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, apiAppName, acrPull)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPull)
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource workerPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, workerAppName, acrPull)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPull)
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource deployPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, deployIdentityName, acrPush)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPush)
    principalId: deployPrincipalId
    principalType: 'ServicePrincipal'
  }
}

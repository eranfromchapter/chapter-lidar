// Log Analytics workspace that receives Container Apps console and system logs.

@description('Log Analytics workspace name.')
param workspaceName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Days to keep logs.')
@minValue(30)
@maxValue(730)
param retentionInDays int

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id

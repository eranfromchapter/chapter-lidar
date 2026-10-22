// Role assignments inside the environment resource group.
//
// api identity:     Storage Blob Data Contributor + Storage Blob Delegator (storage account),
//                   Key Vault Secrets User (vault).
// worker identity:  Storage Blob Data Reader (storage account) to read originals for checks,
//                   Storage Blob Data Contributor on the `reports` container only (it writes
//                   the spatial report PDFs there), Key Vault Secrets User (vault) for the HUB
//                   credential.
// admin group:      Key Vault Secrets Officer (vault) to set secret values.
// deploy identity:  Contributor on the two container apps and the migration job (update image,
//                   start the job), Reader on the resource group.

@description('Storage account name.')
param storageAccountName string

@description('Name of the container of the spatial report PDFs.')
param reportsContainerName string

@description('Key Vault name.')
param keyVaultName string

@description('API container app name.')
param apiAppName string

@description('Worker container app name.')
param workerAppName string

@description('Migration job name.')
param migrateJobName string

@description('Principal ID of the API system-assigned identity.')
param apiPrincipalId string

@description('Principal ID of the worker system-assigned identity.')
param workerPrincipalId string

@description('Object ID of the admin Entra group.')
param adminGroupObjectId string

@description('Deploy identity name (used for stable role assignment names).')
param deployIdentityName string

@description('Principal ID of the GitHub deploy identity.')
param deployPrincipalId string

// Built-in role definition IDs.
var roles = {
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  storageBlobDelegator: 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  keyVaultSecretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource apiApp 'Microsoft.App/containerApps@2024-03-01' existing = {
  name: apiAppName
}

resource workerApp 'Microsoft.App/containerApps@2024-03-01' existing = {
  name: workerAppName
}

resource migrateJob 'Microsoft.App/jobs@2024-03-01' existing = {
  name: migrateJobName
}

resource apiBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, apiAppName, roles.storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.storageBlobDataContributor
    )
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource apiBlobDelegator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, apiAppName, roles.storageBlobDelegator)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.storageBlobDelegator
    )
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource apiSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, apiAppName, roles.keyVaultSecretsUser)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.keyVaultSecretsUser
    )
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource workerBlobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, workerAppName, roles.storageBlobDataReader)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.storageBlobDataReader
    )
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: storage
  name: 'default'
}

resource reportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = {
  parent: blobService
  name: reportsContainerName
}

resource workerReportsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(reportsContainer.id, workerAppName, roles.storageBlobDataContributor)
  scope: reportsContainer
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.storageBlobDataContributor
    )
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource workerSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, workerAppName, roles.keyVaultSecretsUser)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.keyVaultSecretsUser
    )
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource adminSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, adminGroupObjectId, roles.keyVaultSecretsOfficer)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.keyVaultSecretsOfficer
    )
    principalId: adminGroupObjectId
    principalType: 'Group'
  }
}

resource deployApiContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(apiApp.id, deployIdentityName, roles.contributor)
  scope: apiApp
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.contributor
    )
    principalId: deployPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource deployWorkerContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workerApp.id, deployIdentityName, roles.contributor)
  scope: workerApp
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.contributor
    )
    principalId: deployPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource deployMigrateContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(migrateJob.id, deployIdentityName, roles.contributor)
  scope: migrateJob
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.contributor
    )
    principalId: deployPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource deployGroupReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deployIdentityName, roles.reader)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.reader)
    principalId: deployPrincipalId
    principalType: 'ServicePrincipal'
  }
}

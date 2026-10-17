// Key Vault for station secrets (for example `hub-service-credential`).
// RBAC authorization only (no access policies), soft delete and purge protection on.
// This template creates no secret values; an admin sets them (see infra/README.md).

@description('Key Vault name (globally unique, 3-24 characters).')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Days a deleted vault or secret stays recoverable. Fixed after the vault is created.')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

output keyVaultName string = vault.name
output vaultUri string = vault.properties.vaultUri

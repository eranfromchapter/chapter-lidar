// Storage account for capture originals and the station's spatial reports.
//
// - StorageV2, HTTPS only, TLS 1.2 minimum, no public blob access.
// - Shared key access is disabled. The station signs uploads and downloads with user-delegation
//   SAS obtained through its managed identity (Storage Blob Delegator + Storage Blob Data
//   Contributor), so no account key is ever needed or stored.
// - Blob versioning, blob soft delete and container soft delete are on.
// - Container `originals` has version-level immutability (WORM) support and a default
//   time-based retention policy: every blob version written to it is protected from overwrite
//   and delete for `originalsRetentionDays` days after it is created.

@description('Storage account name (globally unique, 3-24 lowercase letters and digits).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Replication SKU.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
])
param skuName string

@description('Days each blob version in `originals` is immutable after creation (time-based retention).')
@minValue(1)
@maxValue(146000)
param originalsRetentionDays int

@description('Days deleted blobs and containers stay recoverable (soft delete).')
@minValue(1)
@maxValue(365)
param softDeleteDays int

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: skuName
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    allowCrossTenantReplication: false
    // Phones upload over the internet with short-lived SAS, so the public endpoint stays on.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: softDeleteDays
      allowPermanentDelete: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: softDeleteDays
    }
  }
}

resource originals 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'originals'
  properties: {
    publicAccess: 'None'
    immutableStorageWithVersioning: {
      enabled: true
    }
  }
}

// Default time-based retention policy for the container. It is created unlocked; locking is a
// separate, irreversible admin action (see infra/README.md).
resource originalsRetention 'Microsoft.Storage/storageAccounts/blobServices/containers/immutabilityPolicies@2023-05-01' = {
  parent: originals
  name: 'default'
  properties: {
    immutabilityPeriodSinceCreationInDays: originalsRetentionDays
    allowProtectedAppendWrites: false
    allowProtectedAppendWritesAll: false
  }
}

// The station's spatial report PDFs (one per verdict, written once by the worker, read through
// short-lived links by the api). Blob versioning and soft delete come from the blob service; no
// immutability policy: they are derived documents, not originals.
resource reports 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'reports'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storage.name
output blobEndpoint string = storage.properties.primaryEndpoints.blob
output originalsContainerName string = originals.name
output reportsContainerName string = reports.name

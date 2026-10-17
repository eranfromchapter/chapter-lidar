// Azure Database for PostgreSQL Flexible Server, Entra ID authentication only.
// Password authentication is disabled, so there is no admin password anywhere.
// The Entra admin is a group; app identities get database roles through a one-time SQL step
// (see infra/README.md).

@description('Server name.')
param serverName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Database created for the station.')
param databaseName string

@description('Compute SKU name, for example Standard_B1ms.')
param skuName string

@description('Compute tier.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string

@description('Storage size in GB.')
@minValue(32)
param storageSizeGB int

@description('Backup retention in days.')
@minValue(7)
@maxValue(35)
param backupRetentionDays int

@description('Object ID of the Entra group that administers the server.')
param adminGroupObjectId string

@description('Display name of that Entra group.')
param adminGroupName string

@description('Add the "allow Azure services" firewall rule (0.0.0.0). Needed while the Container Apps environment has no VNet.')
param allowAzureServices bool

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: '16'
    createMode: 'Default'
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: tenant().tenantId
    }
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource allowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = if (allowAzureServices) {
  parent: server
  name: 'AllowAllAzureServicesAndResourcesWithinAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource entraAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: server
  name: adminGroupObjectId
  properties: {
    principalType: 'Group'
    principalName: adminGroupName
    tenantId: tenant().tenantId
  }
  dependsOn: [
    database
    allowAzure
  ]
}

output serverName string = server.name
output fqdn string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name

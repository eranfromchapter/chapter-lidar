// Chapter Capture station infrastructure.
//
// Scope: subscription. One deployment per environment creates the resource group
// rg-chapter-capture-<env> and everything in it. The container registry is shared by both
// environments and is created by the deployment that has createRegistry = true (production);
// the other environment only adds its role assignments to it.
//
// No secret value appears in this template or its parameter files:
// - Azure access from GitHub Actions uses an OIDC federated credential (no client secret).
// - Postgres uses Entra ID authentication only (password authentication disabled); the apps and
//   the migration job sign in with their own managed identity (DB_AUTH=entra).
// - Storage has shared key access disabled; the station issues user-delegation SAS.
// - Secrets such as `hub-service-credential` live in Key Vault and are set by an admin.
//
// See infra/README.md for the deployment order and the one-time admin steps.

targetScope = 'subscription'

@description('Deployment environment. Drives every resource name.')
@allowed([
  'staging'
  'production'
])
param environmentName string

@description('Azure region for every resource. Defaults to East US 2 (closest region to New York and Miami).')
param location string = 'eastus2'

@description('GitHub repository (owner/repo) whose Actions jobs may deploy, via OIDC. Change it when the repo moves orgs.')
@minLength(3)
param githubRepository string

@description('Object ID of the Entra group that administers Chapter Capture (Postgres Entra admin, Key Vault Secrets Officer).')
@minLength(36)
@maxLength(36)
param adminGroupObjectId string

@description('Display name of that Entra group, exactly as in Entra ID.')
@minLength(1)
param adminGroupName string

@description('Accepted Entra token audiences for the station API: the station app registration client ID and/or App ID URI, comma-separated (ENTRA_AUDIENCE).')
@minLength(1)
param entraAudience string

@description('HUB REST API base URL for HUB_BASE_URL (https).')
@minLength(9)
param hubBaseUrl string

@description('Create the shared container registry in this deployment. True for exactly one environment.')
param createRegistry bool

@description('Resource group that holds (or will hold) the shared container registry.')
param registryResourceGroupName string

@description('Container registry SKU.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param registrySku string = 'Basic'

@description('First deployment of this environment: skip ACR and Key Vault references, which need role assignments that do not exist yet.')
param bootstrap bool = false

@description('API image, also used by the migration job. Empty uses the public placeholder image (listens on 8080) until the first app deploy.')
param apiImage string = ''

@description('Worker image. Empty uses the public placeholder image until the first app deploy.')
param workerImage string = ''

@description('Days each blob version in the originals container is immutable after creation.')
@minValue(1)
@maxValue(146000)
param originalsRetentionDays int

@description('Storage replication SKU.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
])
param storageSku string

@description('Days deleted blobs and containers stay recoverable.')
@minValue(1)
@maxValue(365)
param blobSoftDeleteDays int

@description('Days a deleted Key Vault or secret stays recoverable. Fixed when the vault is created.')
@minValue(7)
@maxValue(90)
param keyVaultSoftDeleteDays int

@description('Log Analytics retention in days.')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Postgres compute SKU name.')
param postgresSkuName string = 'Standard_B1ms'

@description('Postgres compute tier.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param postgresSkuTier string = 'Burstable'

@description('Postgres storage in GB.')
@minValue(32)
param postgresStorageSizeGB int = 32

@description('Postgres backup retention in days.')
@minValue(7)
@maxValue(35)
param postgresBackupRetentionDays int = 7

@description('Allow Azure services through the Postgres firewall (needed while there is no VNet).')
param postgresAllowAzureServices bool = true

@description('API CPU cores, as a string.')
param apiCpu string = '0.5'

@description('API memory.')
param apiMemory string = '1Gi'

@description('Worker CPU cores, as a string.')
param workerCpu string = '1.0'

@description('Worker memory.')
param workerMemory string = '2Gi'

@minValue(0)
param apiMinReplicas int = 0

@minValue(1)
param apiMaxReplicas int = 3

@description('The worker polls the job queue, so it needs at least one running replica.')
@minValue(1)
param workerMinReplicas int = 1

@minValue(1)
param workerMaxReplicas int = 1

// Key Vault and storage account names are limited to 24 characters, so they use a short
// environment token (decided by Eran 2026-10-17, spec F12). Every other name uses the long one.
var shortEnv = {
  staging: 'stg'
  production: 'prod'
}

// Fixed names shared with the GitHub workflows. Change them only together with .github/.
var names = {
  resourceGroup: 'rg-chapter-capture-${environmentName}'
  apiApp: 'ca-capture-api-${environmentName}'
  workerApp: 'ca-capture-worker-${environmentName}'
  migrateJob: 'caj-capture-migrate-${environmentName}'
  registry: 'acrchaptercapture'
  storage: 'stchaptercapture${shortEnv[environmentName]}'
  keyVault: 'kv-chapter-capture-${shortEnv[environmentName]}'
  postgres: 'pg-chapter-capture-${environmentName}'
  // Not referenced by the workflows.
  logAnalytics: 'log-chapter-capture-${environmentName}'
  containerAppsEnvironment: 'cae-chapter-capture-${environmentName}'
  deployIdentity: 'id-chapter-capture-deploy-${environmentName}'
}

var databaseName = 'chapter_capture'

// Public Microsoft sample image that serves HTTP on 8080. Used only until the first real deploy.
var placeholderImage = 'mcr.microsoft.com/dotnet/samples:aspnetapp'

var tags = {
  app: 'chapter-capture'
  env: environmentName
}

var registryLoginServer = '${names.registry}${environment().suffixes.acrLoginServer}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: names.resourceGroup
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    workspaceName: names.logAnalytics
    location: location
    tags: tags
    retentionInDays: logRetentionDays
  }
}

module registry 'modules/registry.bicep' = if (createRegistry) {
  name: 'registry'
  scope: resourceGroup(registryResourceGroupName)
  params: {
    registryName: names.registry
    location: location
    tags: {
      app: 'chapter-capture'
      env: 'shared'
    }
    sku: registrySku
  }
  dependsOn: [
    rg
  ]
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    storageAccountName: names.storage
    location: location
    tags: tags
    skuName: storageSku
    originalsRetentionDays: originalsRetentionDays
    softDeleteDays: blobSoftDeleteDays
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    keyVaultName: names.keyVault
    location: location
    tags: tags
    softDeleteRetentionInDays: keyVaultSoftDeleteDays
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  scope: rg
  params: {
    serverName: names.postgres
    location: location
    tags: tags
    databaseName: databaseName
    skuName: postgresSkuName
    skuTier: postgresSkuTier
    storageSizeGB: postgresStorageSizeGB
    backupRetentionDays: postgresBackupRetentionDays
    adminGroupObjectId: adminGroupObjectId
    adminGroupName: adminGroupName
    allowAzureServices: postgresAllowAzureServices
  }
}

module apps 'modules/containerapps.bicep' = {
  name: 'containerapps'
  scope: rg
  params: {
    environmentName: names.containerAppsEnvironment
    apiAppName: names.apiApp
    workerAppName: names.workerApp
    migrateJobName: names.migrateJob
    location: location
    tags: tags
    logAnalyticsWorkspaceName: monitoring.outputs.workspaceName
    registryLoginServer: registryLoginServer
    keyVaultUri: keyVault.outputs.vaultUri
    blobEndpoint: storage.outputs.blobEndpoint
    originalsContainerName: storage.outputs.originalsContainerName
    reportsContainerName: storage.outputs.reportsContainerName
    postgresHost: postgres.outputs.fqdn
    postgresDatabase: postgres.outputs.databaseName
    hubBaseUrl: hubBaseUrl
    entraAudience: entraAudience
    bootstrap: bootstrap
    apiImage: empty(apiImage) ? placeholderImage : apiImage
    workerImage: empty(workerImage) ? placeholderImage : workerImage
    apiCpu: apiCpu
    apiMemory: apiMemory
    workerCpu: workerCpu
    workerMemory: workerMemory
    apiMinReplicas: apiMinReplicas
    apiMaxReplicas: apiMaxReplicas
    workerMinReplicas: workerMinReplicas
    workerMaxReplicas: workerMaxReplicas
  }
}

module deployIdentity 'modules/deploy-identity.bicep' = {
  name: 'deploy-identity'
  scope: rg
  params: {
    identityName: names.deployIdentity
    location: location
    tags: tags
    githubRepository: githubRepository
    githubEnvironment: environmentName
  }
}

module roles 'modules/roles.bicep' = {
  name: 'roles'
  scope: rg
  params: {
    storageAccountName: storage.outputs.storageAccountName
    reportsContainerName: storage.outputs.reportsContainerName
    keyVaultName: keyVault.outputs.keyVaultName
    apiAppName: names.apiApp
    workerAppName: names.workerApp
    migrateJobName: names.migrateJob
    apiPrincipalId: apps.outputs.apiPrincipalId
    workerPrincipalId: apps.outputs.workerPrincipalId
    adminGroupObjectId: adminGroupObjectId
    deployIdentityName: names.deployIdentity
    deployPrincipalId: deployIdentity.outputs.principalId
  }
}

module registryRoles 'modules/registry-roles.bicep' = {
  name: 'registry-roles-${environmentName}'
  scope: resourceGroup(registryResourceGroupName)
  params: {
    registryName: names.registry
    apiAppName: names.apiApp
    workerAppName: names.workerApp
    migrateJobName: names.migrateJob
    deployIdentityName: names.deployIdentity
    apiPrincipalId: apps.outputs.apiPrincipalId
    workerPrincipalId: apps.outputs.workerPrincipalId
    migratePrincipalId: apps.outputs.migratePrincipalId
    deployPrincipalId: deployIdentity.outputs.principalId
  }
  dependsOn: [
    registry
  ]
}

output resourceGroupName string = rg.name
output apiAppName string = names.apiApp
output workerAppName string = names.workerApp
output migrateJobName string = names.migrateJob
output apiFqdn string = apps.outputs.apiFqdn
output registryLoginServer string = registryLoginServer
output storageAccountName string = storage.outputs.storageAccountName
output keyVaultName string = keyVault.outputs.keyVaultName
output postgresHost string = postgres.outputs.fqdn
output postgresDatabase string = databaseName
@description('Set as the GitHub environment variable AZURE_CLIENT_ID (not a secret).')
output deployClientId string = deployIdentity.outputs.clientId
output apiPrincipalId string = apps.outputs.apiPrincipalId
output workerPrincipalId string = apps.outputs.workerPrincipalId
output migratePrincipalId string = apps.outputs.migratePrincipalId

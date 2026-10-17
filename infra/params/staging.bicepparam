// Staging parameters. No secrets: every value here is safe to commit.
// The admin group object ID and name and the Entra audience come from environment variables
// at deploy time (see infra/README.md). They are identifiers, not secrets, but are
// tenant-specific.
using '../main.bicep'

param environmentName = 'staging'
param location = 'eastus2'
param githubRepository = 'eranfromchapter/chapter-capture'

param adminGroupObjectId = readEnvironmentVariable('CAPTURE_ADMIN_GROUP_OBJECT_ID', '')
param adminGroupName = readEnvironmentVariable('CAPTURE_ADMIN_GROUP_NAME', '')

// Station app registration audience(s) for ENTRA_AUDIENCE (client ID and/or App ID URI).
param entraAudience = readEnvironmentVariable('CAPTURE_ENTRA_AUDIENCE', '')

// The shared registry is created by the production deployment.
param createRegistry = false
param registryResourceGroupName = 'rg-chapter-capture-production'

param bootstrap = bool(readEnvironmentVariable('CAPTURE_BOOTSTRAP', 'false'))
param apiImage = readEnvironmentVariable('CAPTURE_API_IMAGE', '')
param workerImage = readEnvironmentVariable('CAPTURE_WORKER_IMAGE', '')

// Short retention so staging test data can expire.
param originalsRetentionDays = 1
param storageSku = 'Standard_LRS'
param blobSoftDeleteDays = 7
param keyVaultSoftDeleteDays = 7
param logRetentionDays = 30

param postgresSkuName = 'Standard_B1ms'
param postgresSkuTier = 'Burstable'
param postgresStorageSizeGB = 32
param postgresBackupRetentionDays = 7

param apiMinReplicas = 0
param apiMaxReplicas = 2
param workerMinReplicas = 1
param workerMaxReplicas = 1

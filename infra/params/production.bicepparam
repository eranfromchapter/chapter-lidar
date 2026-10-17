// Production parameters. No secrets: every value here is safe to commit.
// The admin group object ID and name come from environment variables at deploy time
// (see infra/README.md); they are identifiers, not secrets, but are tenant-specific.
using '../main.bicep'

param environmentName = 'production'
param location = 'eastus2'
param githubRepository = 'eranfromchapter/chapter-capture'

param adminGroupObjectId = readEnvironmentVariable('CAPTURE_ADMIN_GROUP_OBJECT_ID', '')
param adminGroupName = readEnvironmentVariable('CAPTURE_ADMIN_GROUP_NAME', '')

// Production owns the shared registry acrchaptercapture.
param createRegistry = true
param registryResourceGroupName = 'rg-chapter-capture-production'
param registrySku = 'Basic'

param bootstrap = bool(readEnvironmentVariable('CAPTURE_BOOTSTRAP', 'false'))
param apiImage = readEnvironmentVariable('CAPTURE_API_IMAGE', '')
param workerImage = readEnvironmentVariable('CAPTURE_WORKER_IMAGE', '')

// 7 years (7 x 365 + 2 leap days) of immutability for client originals.
param originalsRetentionDays = 2557
// Geo-zone-redundant: originals are irreplaceable.
param storageSku = 'Standard_GZRS'
param blobSoftDeleteDays = 30
param keyVaultSoftDeleteDays = 90
param logRetentionDays = 90

param postgresSkuName = 'Standard_B2s'
param postgresSkuTier = 'Burstable'
param postgresStorageSizeGB = 64
param postgresBackupRetentionDays = 35

param apiMinReplicas = 1
param apiMaxReplicas = 5
param workerMinReplicas = 1
param workerMaxReplicas = 1

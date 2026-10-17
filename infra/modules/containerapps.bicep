// Container Apps environment (logs to Log Analytics) with:
// - api: external HTTPS ingress to port 8080, /health readiness probe.
// - worker: no ingress; polls the Postgres job queue, runs checks and HUB publish.
// - migrate job: manually triggered; applies the Postgres migrations with the api image.
// Each has a system-assigned managed identity for ACR pulls, Key Vault references and Blob
// access. No secret value is set here: secrets are Key Vault references by name.
//
// Environment variable names match station/api/src/core/config.ts.
//
// `bootstrap` = true is for the very first deployment only. A system-assigned identity does not
// exist until its app or job is created, so its AcrPull and Key Vault role assignments cannot
// exist yet either. In bootstrap mode nothing references the registry or Key Vault, the api has
// no /health probes, and everything runs the public placeholder image. Run again with
// bootstrap = false once roles and the Key Vault secrets are in place.

@description('Container Apps environment name.')
param environmentName string

@description('API container app name.')
param apiAppName string

@description('Worker container app name.')
param workerAppName string

@description('Migration job name.')
param migrateJobName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Existing Log Analytics workspace name in this resource group.')
param logAnalyticsWorkspaceName string

@description('Registry login server, for example acrchaptercapture.azurecr.io.')
param registryLoginServer string

@description('Key Vault URI (ends with a slash).')
param keyVaultUri string

@description('Blob endpoint of the originals storage account.')
param blobEndpoint string

@description('Name of the originals container.')
param originalsContainerName string

@description('Accepted Entra token audiences for the station API (comma-separated).')
param entraAudience string

@description('First deployment: no registry or Key Vault references and no probes yet.')
param bootstrap bool

@description('API image reference (also used by the migration job).')
param apiImage string

@description('Worker image reference.')
param workerImage string

@description('API CPU cores, as a string (for example "0.5").')
param apiCpu string

@description('API memory, for example "1Gi".')
param apiMemory string

@description('Worker CPU cores, as a string (for example "1.0").')
param workerCpu string

@description('Worker memory, for example "2Gi".')
param workerMemory string

@minValue(0)
param apiMinReplicas int

@minValue(1)
param apiMaxReplicas int

@minValue(0)
param workerMinReplicas int

@minValue(1)
param workerMaxReplicas int

// Key Vault secret names. Only names live here; an admin sets the values.
var hubSecretName = 'hub-service-credential'
var databaseSecretName = 'database-url'

// The api image's migration entrypoint (see station/api/src/core/migrate-main.ts). The runtime
// image has production dependencies and dist/ only, so `npm run migrate` (tsx on src/) cannot
// run in it. Working directory is the image's /app/station/api.
var migrateCommand = [
  'node'
  'dist/core/migrate-main.js'
]

var loginEndpoint = environment().authentication.loginEndpoint
var tenantId = tenant().tenantId

var registries = bootstrap
  ? []
  : [
      {
        server: registryLoginServer
        identity: 'system'
      }
    ]

var databaseSecret = {
  name: databaseSecretName
  keyVaultUrl: '${keyVaultUri}secrets/${databaseSecretName}'
  identity: 'system'
}

var hubSecret = {
  name: hubSecretName
  keyVaultUrl: '${keyVaultUri}secrets/${hubSecretName}'
  identity: 'system'
}

var appSecrets = bootstrap ? [] : [databaseSecret, hubSecret]
var jobSecrets = bootstrap ? [] : [databaseSecret]

var databaseEnv = bootstrap
  ? []
  : [
      {
        name: 'DATABASE_URL'
        secretRef: databaseSecretName
      }
    ]

var hubSecretEnv = bootstrap
  ? []
  : [
      {
        name: 'HUB_SERVICE_CREDENTIAL'
        secretRef: hubSecretName
      }
    ]

// Settings shared by the api, the worker and the migration job (station/api/src/core/config.ts).
var commonEnv = [
  {
    name: 'NODE_ENV'
    value: 'production'
  }
  {
    name: 'MIGRATE_ON_START'
    value: 'false'
  }
  {
    name: 'ENTRA_TENANT_ID'
    value: tenantId
  }
  {
    name: 'ENTRA_AUDIENCE'
    value: entraAudience
  }
  {
    name: 'ENTRA_ISSUER'
    value: '${loginEndpoint}${tenantId}/v2.0'
  }
  {
    name: 'ENTRA_JWKS_URL'
    value: '${loginEndpoint}${tenantId}/discovery/v2.0/keys'
  }
  {
    name: 'HUB_MODE'
    value: 'live'
  }
  {
    name: 'AZURE_STORAGE_ACCOUNT_URL'
    value: blobEndpoint
  }
  {
    name: 'STORAGE_ORIGINALS_CONTAINER'
    value: originalsContainerName
  }
]

// Readiness uses /health (503 while the registry database is unreachable, so traffic stops).
// Liveness and startup only check the port, so a database outage does not restart replicas.
var apiProbes = bootstrap
  ? []
  : [
      {
        type: 'Startup'
        tcpSocket: {
          port: 8080
        }
        initialDelaySeconds: 1
        periodSeconds: 10
        timeoutSeconds: 3
        failureThreshold: 10
      }
      {
        type: 'Readiness'
        httpGet: {
          path: '/health'
          port: 8080
          scheme: 'HTTP'
        }
        initialDelaySeconds: 5
        periodSeconds: 10
        timeoutSeconds: 3
        successThreshold: 1
        failureThreshold: 3
      }
      {
        type: 'Liveness'
        tcpSocket: {
          port: 8080
        }
        initialDelaySeconds: 10
        periodSeconds: 30
        timeoutSeconds: 5
        failureThreshold: 5
      }
    ]

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: apiAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: managedEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: registries
      secrets: appSecrets
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          resources: {
            cpu: json(apiCpu)
            memory: apiMemory
          }
          env: concat(
            commonEnv,
            [
              {
                name: 'PORT'
                value: '8080'
              }
            ],
            databaseEnv,
            hubSecretEnv
          )
          probes: apiProbes
        }
      ]
      scale: {
        minReplicas: apiMinReplicas
        maxReplicas: apiMaxReplicas
      }
    }
  }
}

resource worker 'Microsoft.App/containerApps@2024-03-01' = {
  name: workerAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: managedEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      registries: registries
      secrets: appSecrets
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: workerImage
          resources: {
            cpu: json(workerCpu)
            memory: workerMemory
          }
          env: concat(commonEnv, databaseEnv, hubSecretEnv)
        }
      ]
      scale: {
        minReplicas: workerMinReplicas
        maxReplicas: workerMaxReplicas
      }
    }
  }
}

resource migrate 'Microsoft.App/jobs@2024-03-01' = {
  name: migrateJobName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: managedEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: registries
      secrets: jobSecrets
    }
    template: {
      containers: [
        {
          name: 'migrate'
          image: apiImage
          command: migrateCommand
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: concat(commonEnv, databaseEnv)
        }
      ]
    }
  }
}

output apiPrincipalId string = api.identity.principalId
output workerPrincipalId string = worker.identity.principalId
output migratePrincipalId string = migrate.identity.principalId
output apiFqdn string = api.properties.configuration.ingress.fqdn

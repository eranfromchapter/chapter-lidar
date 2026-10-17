// Container Apps environment (logs to Log Analytics) with two apps:
// - api: external HTTPS ingress to port 8080.
// - worker: no ingress; polls the Postgres job queue.
// Both use a system-assigned managed identity for ACR pulls, Key Vault references, Blob and
// Postgres (Entra) access. No secret value is set here.
//
// `bootstrap` = true is for the very first deployment only. A system-assigned identity does not
// exist until its app is created, so its AcrPull and Key Vault role assignments cannot exist yet
// either. In bootstrap mode the apps skip the registry and Key Vault references and run the
// public placeholder image. Run again with bootstrap = false once roles and the
// `hub-service-credential` secret are in place.

@description('Container Apps environment name.')
param environmentName string

@description('API container app name.')
param apiAppName string

@description('Worker container app name.')
param workerAppName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Deployment environment (staging or production), passed to the apps as STATION_ENV.')
param stationEnv string

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

@description('Postgres server FQDN.')
param postgresHost string

@description('Postgres database name.')
param postgresDatabase string

@description('First deployment: no registry or Key Vault references yet.')
param bootstrap bool

@description('API image reference.')
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

// Name of the Key Vault secret that holds the HUB service credential. Only the name lives here.
var hubSecretName = 'hub-service-credential'

var registries = bootstrap
  ? []
  : [
      {
        server: registryLoginServer
        identity: 'system'
      }
    ]

var hubSecrets = bootstrap
  ? []
  : [
      {
        name: hubSecretName
        keyVaultUrl: '${keyVaultUri}secrets/${hubSecretName}'
        identity: 'system'
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

var commonEnv = [
  {
    name: 'NODE_ENV'
    value: 'production'
  }
  {
    name: 'STATION_ENV'
    value: stationEnv
  }
  {
    name: 'AZURE_STORAGE_BLOB_URL'
    value: blobEndpoint
  }
  {
    name: 'ORIGINALS_CONTAINER'
    value: originalsContainerName
  }
  {
    name: 'KEY_VAULT_URI'
    value: keyVaultUri
  }
  {
    name: 'PGHOST'
    value: postgresHost
  }
  {
    name: 'PGPORT'
    value: '5432'
  }
  {
    name: 'PGDATABASE'
    value: postgresDatabase
  }
  {
    name: 'PGSSLMODE'
    value: 'require'
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
      secrets: hubSecrets
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
              {
                name: 'PGUSER'
                value: apiAppName
              }
            ],
            hubSecretEnv
          )
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
          env: concat(commonEnv, [
            {
              name: 'PGUSER'
              value: workerAppName
            }
          ])
        }
      ]
      scale: {
        minReplicas: workerMinReplicas
        maxReplicas: workerMaxReplicas
      }
    }
  }
}

output apiPrincipalId string = api.identity.principalId
output workerPrincipalId string = worker.identity.principalId
output apiFqdn string = api.properties.configuration.ingress.fqdn

// Azure Container Registry shared by staging and production.
// Admin user and anonymous pull are off: apps pull with their managed identity (AcrPull) and
// GitHub Actions pushes with its OIDC deploy identity (AcrPush).

@description('Registry name (globally unique, lowercase letters and digits only).')
param registryName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Registry SKU.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

output loginServer string = registry.properties.loginServer

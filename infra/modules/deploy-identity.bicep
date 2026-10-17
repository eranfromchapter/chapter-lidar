// User-assigned identity that GitHub Actions signs in as through OIDC (no client secret).
// The federated credential only trusts jobs of `githubRepository` that run in the GitHub
// environment named `githubEnvironment`, so production deploys stay behind that environment's
// required approval.

@description('Identity name.')
param identityName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('GitHub repository in owner/repo form.')
param githubRepository string

@description('GitHub environment whose jobs may use this identity.')
param githubEnvironment string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource githubFederation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: identity
  name: 'github-${githubEnvironment}'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubRepository}:environment:${githubEnvironment}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId

targetScope = 'subscription'

param environmentName string
param location string
param sessionId string
param deployedBy string
param createdAt string
param deployerObjectId string
param resourceGroupName string
param appServicePlanName string
param appServiceName string
param managedIdentityName string
param appInsightsName string
param containerImage string
param acrName string
param acrLoginServer string
param foundryAccountName string
param logAnalyticsWorkspaceId string
param agentEndpoint string
param agentName string
param agentVersion string

var tags = {
  'app-onboard-skill': 'true'
  'app-onboard-session-id': sessionId
  'created-at': createdAt
  environment: environmentName
  'deployed-by': deployedBy
}

resource targetResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: resourceGroupName
}

module managedIdentity './modules/managed-identity.bicep' = {
  name: 'managed-identity'
  scope: targetResourceGroup
  params: {
    location: location
    tags: tags
    identityName: managedIdentityName
  }
}

module appServicePlan './modules/app-service-plan.bicep' = {
  name: 'app-service-plan'
  scope: targetResourceGroup
  params: {
    location: location
    tags: tags
    planName: appServicePlanName
  }
}

module appInsights './modules/app-insights.bicep' = {
  name: 'application-insights'
  scope: targetResourceGroup
  params: {
    location: location
    tags: tags
    appInsightsName: appInsightsName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments'
  scope: targetResourceGroup
  params: {
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    acrName: acrName
    foundryAccountName: foundryAccountName
  }
}

module appService './modules/app-service.bicep' = {
  name: 'app-service'
  scope: targetResourceGroup
  params: {
    location: location
    tags: tags
    appServiceName: appServiceName
    appServicePlanId: appServicePlan.outputs.id
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityClientId: managedIdentity.outputs.clientId
    containerImage: containerImage
    acrLoginServer: acrLoginServer
    agentEndpoint: agentEndpoint
    agentName: agentName
    agentVersion: agentVersion
    appInsightsConnectionString: appInsights.outputs.connectionString
  }
  dependsOn: [
    roleAssignments
  ]
}

output appServiceUrl string = 'https://${appService.outputs.defaultHostName}'
output appServiceResourceId string = appService.outputs.id
output managedIdentityResourceId string = managedIdentity.outputs.id
output deployerObjectIdUsed string = deployerObjectId
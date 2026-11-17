param location string
param tags object
param appServiceName string
param appServicePlanId string
param managedIdentityId string
param managedIdentityClientId string
param containerImage string
param acrLoginServer string
param agentEndpoint string
param agentName string
param agentVersion string
param appInsightsConnectionString string

resource appService 'Microsoft.Web/sites@2026-08-01' = {
  name: appServiceName
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOCKER|${containerImage}'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      healthCheckPath: '/api/agent/readiness'
      http20Enabled: true
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: managedIdentityClientId
      appSettings: [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acrLoginServer}'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8000'
        }
        {
          name: 'HOST'
          value: '0.0.0.0'
        }
        {
          name: 'PORT'
          value: '8000'
        }
        {
          name: 'CALDOVA_AGENT_ENDPOINT'
          value: agentEndpoint
        }
        {
          name: 'CALDOVA_AGENT_NAME'
          value: agentName
        }
        {
          name: 'CALDOVA_AGENT_VERSION'
          value: agentVersion
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: managedIdentityClientId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
      ]
    }
  }
}

resource scmPublishingPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2026-08-01' = {
  parent: appService
  name: 'scm'
  properties: {
    allow: false
  }
}

resource ftpPublishingPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2026-08-01' = {
  parent: appService
  name: 'ftp'
  properties: {
    allow: false
  }
}

output id string = appService.id
output defaultHostName string = appService.properties.defaultHostName
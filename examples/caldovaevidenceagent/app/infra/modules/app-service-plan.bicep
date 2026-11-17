param location string
param tags object
param planName string

resource plan 'Microsoft.Web/serverfarms@2026-08-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

output id string = plan.id
// -----------------------------------------------------------------------------
// Demo: "Fra kode til produksjon" - a resource group, a web app, and the identity
// that is allowed to deploy to it.
//
// Deployed at SUBSCRIPTION scope, because this file creates the resource group
// itself. That is a deliberate teaching point: the pipeline that creates resource
// groups must be allowed to create resource groups, so the IaC identity is
// necessarily more privileged than the app-deploy identity created further down.
// Compare the two role assignments in docs/00-azure-setup.md.
// -----------------------------------------------------------------------------

targetScope = 'subscription'

@description('Short name for the workload. Used as a prefix for every resource name.')
@minLength(3)
@maxLength(12)
param workload string = 'devops-demo'

@description('Environment discriminator, e.g. dev or test.')
@allowed(['dev', 'test'])
param environmentName string = 'dev'

@description('Azure region. Check Free tier availability with: az appservice list-locations --sku F1')
param location string = 'norwayeast'

@description('App Service plan size. F1 is free but capped at 60 CPU-minutes/day per region per subscription; if the cap is hit the app returns HTTP 403 until midnight UTC. B1 removes the cap for about USD 13/month.')
@allowed(['F1', 'B1'])
param appServicePlanSku string = 'F1'

@description('GitHub organisation or user that owns the demo repository.')
param githubOwner string

@description('GitHub repository name, without the owner.')
param githubRepo string

@description('Branch allowed to deploy the application. The federated trust is scoped to exactly this branch.')
param githubBranch string = 'main'

@description('''
Leave true for the "key under the mat" demo: it re-enables SCM basic authentication so a
publish profile exists at all. Azure disables this by default on new apps precisely because
it is the insecure option. Set to false to show the publish-profile workflow failing with 401
while the federated-identity workflow keeps working.
''')
param enableScmBasicAuth bool = true

@description('Deploy Log Analytics and Application Insights for the observability part of the portal tour.')
param enableMonitoring bool = true

var resourceGroupName = 'rg-${workload}-${environmentName}'

var tags = {
  workload: workload
  environment: environmentName
  managedBy: 'bicep'
  purpose: 'Temporary CI/CD demo'
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = if (enableMonitoring) {
  scope: resourceGroup
  name: 'monitoring'
  params: {
    workload: workload
    environmentName: environmentName
    location: location
    tags: tags
  }
}

module webApp 'modules/webapp.bicep' = {
  scope: resourceGroup
  name: 'webapp'
  params: {
    workload: workload
    environmentName: environmentName
    location: location
    tags: tags
    appServicePlanSku: appServicePlanSku
    enableScmBasicAuth: enableScmBasicAuth
    appInsightsConnectionString: enableMonitoring ? monitoring!.outputs.appInsightsConnectionString : ''
  }
}

module deployIdentity 'modules/deploy-identity.bicep' = {
  scope: resourceGroup
  name: 'deploy-identity'
  params: {
    workload: workload
    environmentName: environmentName
    location: location
    tags: tags
    githubOwner: githubOwner
    githubRepo: githubRepo
    githubBranch: githubBranch
  }
}

@description('Name of the resource group everything landed in.')
output resourceGroupName string = resourceGroup.name

@description('Name of the web app, needed by both deploy workflows.')
output webAppName string = webApp.outputs.webAppName

@description('Public URL of the deployed application.')
output webAppUrl string = webApp.outputs.webAppUrl

@description('Client ID of the app-deploy identity. Not a secret: store it as a GitHub *variable*.')
output deployIdentityClientId string = deployIdentity.outputs.clientId

@description('Whether the insecure publish-profile path is currently possible.')
output scmBasicAuthEnabled bool = enableScmBasicAuth

// -----------------------------------------------------------------------------
// Demo: "Fra kode til produksjon" - a web app and the identity allowed to deploy
// to it, all inside one resource group.
//
// Deployed at RESOURCE GROUP scope. The resource group itself is a prerequisite,
// created once by hand, because this demo runs in a subscription where nobody
// should hold subscription-wide rights just to host a lecture demo.
//
// The payoff is that nothing here is subscription-scoped. Every role assignment
// lands on this one resource group, which is exactly the argument the lecture
// makes: scope the role to the resource group, not to the subscription. The two
// identities still differ sharply in how much they can do - see
// docs/00-azure-setup.md for the comparison.
// -----------------------------------------------------------------------------

targetScope = 'resourceGroup'

@description('Short name for the workload. Used as a prefix for every resource name.')
@minLength(3)
@maxLength(12)
param workload string = 'devops-demo'

@description('Environment discriminator, e.g. dev or test.')
@allowed(['dev', 'test'])
param environmentName string = 'dev'

@description('''
Azure region. Defaults to the resource group's own location, which is almost always what
you want. Check Free tier availability with: az appservice list-locations --sku F1
''')
param location string = resourceGroup().location

@description('App Service plan size. F1 is free but capped at 60 CPU-minutes/day per region per subscription; if the cap is hit the app returns HTTP 403 until midnight UTC. B1 removes the cap for about USD 13/month.')
@allowed(['F1', 'B1'])
param appServicePlanSku string = 'F1'

@description('''
GitHub's OIDC subject prefix for this repository, which the federated trust is anchored to.
Read it rather than constructing it - GitHub now pins subjects to immutable numeric IDs:
  gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
''')
param githubSubjectPrefix string

@description('''
Leave true for the "key under the mat" demo: it re-enables SCM basic authentication so a
publish profile exists at all. Azure disables this by default on new apps precisely because
it is the insecure option. Set to false to show the publish-profile workflow failing with 401
while the federated-identity workflow keeps working.
''')
param enableScmBasicAuth bool = true

@description('Deploy Log Analytics and Application Insights for the observability part of the portal tour.')
param enableMonitoring bool = true

var tags = {
  workload: workload
  environment: environmentName
  managedBy: 'bicep'
  purpose: 'Temporary CI/CD demo'
}

module monitoring 'modules/monitoring.bicep' = if (enableMonitoring) {
  name: 'monitoring'
  params: {
    workload: workload
    environmentName: environmentName
    location: location
    tags: tags
  }
}

module webApp 'modules/webapp.bicep' = {
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
  name: 'deploy-identity'
  params: {
    workload: workload
    environmentName: environmentName
    location: location
    tags: tags
    githubSubjectPrefix: githubSubjectPrefix
  }
}

@description('Name of the resource group everything landed in.')
output resourceGroupName string = resourceGroup().name

@description('Name of the web app, needed by both deploy workflows.')
output webAppName string = webApp.outputs.webAppName

@description('Public URL of the deployed application.')
output webAppUrl string = webApp.outputs.webAppUrl

@description('Client ID of the app-deploy identity. Not a secret: store it as a GitHub *variable*.')
output deployIdentityClientId string = deployIdentity.outputs.clientId

@description('Whether the insecure publish-profile path is currently possible.')
output scmBasicAuthEnabled bool = enableScmBasicAuth

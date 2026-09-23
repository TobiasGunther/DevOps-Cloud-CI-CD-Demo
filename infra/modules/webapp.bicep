// App Service plan + web app. Everything the application needs to run, and nothing else.

param workload string
param environmentName string
param location string
param tags object
param appServicePlanSku string
param enableScmBasicAuth bool

@description('Empty string when monitoring is disabled.')
param appInsightsConnectionString string

// Web app names share one global DNS namespace, so a suffix derived from the resource
// group keeps this deployable without hand-picking a name that happens to be free.
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 5)
var webAppName = 'app-${workload}-${environmentName}-${uniqueSuffix}'

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'asp-${workload}-${environmentName}'
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
    tier: appServicePlanSku == 'F1' ? 'Free' : 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true // "reserved" is how ARM spells "this is a Linux plan".
  }
}

resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: webAppName
  location: location
  tags: tags
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      // Always On is not available on the Free tier, and setting it true there fails
      // the deployment outright. On F1 the app unloads after ~20 minutes idle.
      alwaysOn: appServicePlanSku != 'F1'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      healthCheckPath: '/health'
      appSettings: concat(
        [
          // Configuration comes from the environment, not from the artifact.
          // ASP.NET Core maps the "__" separator onto its "Demo:Key" hierarchy.
          {
            name: 'Demo__EnvironmentName'
            value: environmentName
          }
          {
            name: 'Demo__Message'
            value: 'Deployed by a pipeline to Azure App Service (${appServicePlanSku}) in ${location}.'
          }
          {
            name: 'ASPNETCORE_ENVIRONMENT'
            value: 'Production'
          }
        ],
        empty(appInsightsConnectionString) ? [] : [
          {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
            value: appInsightsConnectionString
          }
        ]
      )
    }
  }
}

// ---------------------------------------------------------------------------
// The "key under the mat".
//
// Azure ships new web apps with SCM basic authentication DISABLED, which means no
// publish profile password exists and the publish-profile workflow cannot work.
// Turning it back on is an explicit, auditable decision - which is exactly the point
// being made on the slide. FTP basic auth stays off regardless.
// ---------------------------------------------------------------------------
resource scmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: webApp
  name: 'scm'
  properties: {
    allow: enableScmBasicAuth
  }
}

resource ftpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: webApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

// -----------------------------------------------------------------------------
// The app-deploy identity: the "riktig vei" from the slide, expressed as code.
//
// This is a *user-assigned managed identity*, not an Entra app registration. The
// difference matters in practice: a managed identity is an Azure resource on the ARM
// control plane, so creating one needs no directory permissions at all. In a locked-down
// tenant - a university or a large employer - you usually cannot create an app
// registration, but you can create this.
//
// Nothing here is a secret. There is no password, no certificate and no key to leak.
// Trust is anchored to *who is running the job*: one repository, one branch.
// -----------------------------------------------------------------------------

param workload string
param environmentName string
param location string
param tags object
param githubSubjectPrefix string
param githubBranch string

// Website Contributor. Verified against
// https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/web-and-mobile
// It grants Microsoft.Web/sites/* plus serverFarms/read+join - enough to push code to an
// existing app, but not to create or resize the plan it runs on, and not to touch anything
// else in the subscription.
var websiteContributorRoleId = 'de139f84-1756-47ae-9be6-808fbbe84772'

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${workload}-${environmentName}-deploy'
  location: location
  tags: tags
}

// The federated trust. GitHub presents a signed token describing the workflow run;
// Entra ID checks that the issuer and subject match exactly what is written here and,
// if they do, mints an access token that lives for minutes.
//
// The subject is the security boundary. A fork, a different branch, or a pull request
// from an outside contributor produces a different subject and is refused.
//
// The prefix usually looks like this, with numeric owner and repository IDs:
//
//   repo:octocat@107984787/my-repo@1382946058
//
// GitHub pins the subject to those immutable IDs so that deleting a repository and
// recreating it under the same name does not inherit its access. Older repositories
// still use the plain "repo:owner/name" form. Read yours rather than guessing:
//
//   gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
resource branchCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: deployIdentity
  name: 'github-${githubBranch}'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: '${githubSubjectPrefix}:ref:refs/heads/${githubBranch}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// Least privilege is about scope as much as about role: this binding is on the resource
// group, so the identity is blind to everything else in the subscription.
resource deployRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deployIdentity.id, websiteContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', websiteContributorRoleId)
    principalId: deployIdentity.properties.principalId
    // Declaring the type avoids a spurious failure when the identity is brand new and
    // has not finished replicating through Entra ID yet.
    principalType: 'ServicePrincipal'
  }
}

@description('Client ID. Safe to publish - it identifies the identity, it does not authenticate as it.')
output clientId string = deployIdentity.properties.clientId

output principalId string = deployIdentity.properties.principalId
output identityName string = deployIdentity.name

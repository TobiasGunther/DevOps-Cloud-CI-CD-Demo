<#
.SYNOPSIS
    One-time bootstrap: create the identity the INFRASTRUCTURE pipeline uses.

.DESCRIPTION
    Everything else in this repository is created by that pipeline. This script exists
    only to break the chicken-and-egg problem: something has to create the first
    identity, and it cannot be the pipeline that needs it.

    It creates a user-assigned managed identity rather than an Entra app registration.
    An app registration lives in the Entra directory and many tenants forbid ordinary
    users from creating one; a managed identity is an ordinary Azure resource, so Owner
    on a subscription is enough. Both support the same federated credentials.

    Requires Owner on the target subscription (or Contributor + RBAC Administrator).

.EXAMPLE
    ./scripts/bootstrap-azure.ps1 -GithubOwner TobiasGunther -GithubRepo DevOps-Cloud-CI-CD-Demo
#>
[CmdletBinding()]
param(
    [string]$Workload      = 'devops-demo',
    [string]$Location      = 'norwayeast',
    [string]$GithubOwner   = 'TobiasGunther',
    [string]$GithubRepo    = 'DevOps-Cloud-CI-CD-Demo',
    [string]$GithubBranch  = 'main'
)

$ErrorActionPreference = 'Stop'

$identityRg   = "rg-$Workload-identity"
$identityName = "id-$Workload-iac"

# Verified against learn.microsoft.com/azure/role-based-access-control/built-in-roles
$contributorRole = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
$rbacAdminRole   = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI not found.'
}

$account         = az account show | ConvertFrom-Json
$subscriptionId  = $account.id
$tenantId        = $account.tenantId

Write-Host @"

  Subscription : $($account.name)
                 $subscriptionId
  Tenant       : $tenantId
  Repository   : $GithubOwner/$GithubRepo  (branch: $GithubBranch)
  Identity     : $identityName in $identityRg ($Location)

  This grants the identity Contributor and Role Based Access Control Administrator
  over the WHOLE subscription, because it has to create resource groups and role
  assignments. Use a sandbox subscription, never a shared or production one.

"@

if ((Read-Host 'Continue? [y/N]') -notin @('y', 'Y')) {
    Write-Host 'Aborted.'
    return
}

Write-Host "==> Resource group $identityRg"
az group create --name $identityRg --location $Location `
    --tags workload=$Workload purpose='Temporary CI/CD demo' managedBy='bootstrap script' `
    --output none

Write-Host "==> Managed identity $identityName"
az identity create --name $identityName --resource-group $identityRg --location $Location --output none

$identity    = az identity show --name $identityName --resource-group $identityRg | ConvertFrom-Json
$clientId    = $identity.clientId
$principalId = $identity.principalId

# The "subject" is the security boundary. GitHub signs a token describing the run;
# Entra ID issues an access token only when the subject matches one of these exactly.
# A fork, another branch, or another repository produces a different subject.
function Add-FederatedCredential {
    param([string]$Name, [string]$Subject)

    Write-Host "==> Federated credential $Name"
    Write-Host "    subject: $Subject"
    az identity federated-credential create `
        --name $Name `
        --identity-name $identityName `
        --resource-group $identityRg `
        --issuer 'https://token.actions.githubusercontent.com' `
        --subject $Subject `
        --audiences 'api://AzureADTokenExchange' `
        --output none
}

Add-FederatedCredential -Name "github-$GithubBranch" `
    -Subject "repo:$GithubOwner/${GithubRepo}:ref:refs/heads/$GithubBranch"

# Lets pull requests run what-if against the real subscription without being able to
# merge anything. Read the scope carefully before enabling this on a real system.
Add-FederatedCredential -Name 'github-pull-request' `
    -Subject "repo:$GithubOwner/${GithubRepo}:pull_request"

# Contributor alone is NOT enough: its notActions exclude Microsoft.Authorization/*/Write,
# so it cannot create the role assignment that main.bicep makes for the app-deploy
# identity. Role Based Access Control Administrator supplies exactly that, and is
# narrower than User Access Administrator.
function Add-SubscriptionRole {
    param([string]$RoleId, [string]$Label)

    Write-Host "==> Role assignment: $Label"
    az role assignment create `
        --assignee-object-id $principalId `
        --assignee-principal-type ServicePrincipal `
        --role $RoleId `
        --scope "/subscriptions/$subscriptionId" `
        --output none
}

Add-SubscriptionRole -RoleId $contributorRole -Label 'Contributor (subscription)'
Add-SubscriptionRole -RoleId $rbacAdminRole   -Label 'Role Based Access Control Administrator (subscription)'

Write-Host @"

  Done. None of the values below are secrets: they identify the identity, they do
  not authenticate as it. Store them as repository VARIABLES, not secrets.

    AZURE_IAC_CLIENT_ID    $clientId
    AZURE_TENANT_ID        $tenantId
    AZURE_SUBSCRIPTION_ID  $subscriptionId

  With the GitHub CLI:

    gh variable set AZURE_IAC_CLIENT_ID   --body "$clientId"
    gh variable set AZURE_TENANT_ID       --body "$tenantId"
    gh variable set AZURE_SUBSCRIPTION_ID --body "$subscriptionId"

  Next: run the "Infra - deploy to Azure" workflow, then follow docs/00-azure-setup.md
  to record AZURE_WEBAPP_NAME and AZURE_DEPLOY_CLIENT_ID from its output.

"@

<#
.SYNOPSIS
    One-time bootstrap: create the identity the INFRASTRUCTURE pipeline uses.

.DESCRIPTION
    Everything else in this repository is created by that pipeline. This script exists
    only to break the chicken-and-egg problem: something has to create the first
    identity, and it cannot be the pipeline that needs it.

    Everything lives in ONE resource group, which you create beforehand:

        az group create --name rg-devops-demo-dev --location norwayeast

    and on which you need Owner, or Contributor plus User Access Administrator.
    Nothing here touches the subscription, so this works in a subscription where you
    are trusted with a single resource group and nothing more.

    It creates a user-assigned managed identity rather than an Entra app registration.
    An app registration lives in the Entra directory and many tenants forbid ordinary
    users from creating one; a managed identity is an ordinary Azure resource, so
    rights on a resource group are enough. Both support the same federated credentials.

.EXAMPLE
    ./scripts/bootstrap-azure.ps1
#>
[CmdletBinding()]
param(
    [string]$Workload      = 'devops-demo',
    [string]$Environment   = 'dev',
    [string]$ResourceGroup,
    [string]$GithubOwner   = 'TobiasGunther',
    [string]$GithubRepo    = 'DevOps-Cloud-CI-CD-Demo',
    [string]$GithubBranch  = 'main'
)

$ErrorActionPreference = 'Stop'

if (-not $ResourceGroup) { $ResourceGroup = "rg-$Workload-$Environment" }

# Without this, a failure ends the script instantly. If it was started by
# right-click "Run with PowerShell", the window closes with it and the error is gone
# before anyone can read it. Explain what happened and hold the window open.
trap {
    Write-Host ''
    Write-Host '  --------------------------------------------------------------------'
    Write-Host "  Stopped: $($_.Exception.Message)"
    Write-Host ''
    Write-Host '  Two failures are common here:'
    Write-Host ''
    Write-Host '  RequestDisallowedByPolicy, mentioning multi-factor authentication'
    Write-Host '      Your Azure token was issued without MFA, and some tenants deny'
    Write-Host '      resource writes from such tokens. Sign in again and rerun:'
    Write-Host ''
    Write-Host '          az logout'
    Write-Host '          az login --scope https://management.azure.com//.default'
    Write-Host ''
    Write-Host '  AuthorizationFailed on a role assignment'
    Write-Host '      You can create resources in the group but not grant roles in it.'
    Write-Host '      Ask for Owner, or User Access Administrator alongside Contributor,'
    Write-Host "      on $ResourceGroup."
    Write-Host ''
    Write-Host '  Nothing is left half-built: rerunning is safe, every step is idempotent.'
    Write-Host '  --------------------------------------------------------------------'
    Write-Host ''
    # Only pause when someone is actually watching; never hang an automated run.
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        Read-Host '  Press Enter to close'
    }
    exit 1
}

$identityName = "id-$Workload-iac"

# Verified against learn.microsoft.com/azure/role-based-access-control/built-in-roles
$contributorRole = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
$rbacAdminRole   = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI not found.'
}

# ConvertFrom-Json does not throw on empty input, so a failed "az account show"
# would otherwise sail past with a blank subscription and only fail much later,
# halfway through creating things. Check the exit code explicitly.
$account = az account show 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $account.id) {
    throw 'Not signed in to Azure. Run: az login --scope https://management.azure.com//.default'
}

$subscriptionId = $account.id
$tenantId       = $account.tenantId
$rgScope        = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup"

# The resource group is a prerequisite, not something this script creates. Creating
# one needs subscription rights, which is precisely what this design avoids needing.
$location = az group show --name $ResourceGroup --query location -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or -not $location) {
    Write-Host @"

  Resource group "$ResourceGroup" does not exist in $($account.name).

  Create it, or ask whoever administers the subscription to:

      az group create --name $ResourceGroup --location norwayeast

  You then need Owner on it, or Contributor plus User Access Administrator.

"@
    exit 1
}

# This group is about to hold an identity a public repository can deploy with. If it
# already contains somebody else work, that is worth stopping over.
$existing = az resource list --resource-group $ResourceGroup --query "length(@)" -o tsv 2>$null
if (-not $existing) { $existing = 0 }

Write-Host @"

  Subscription   : $($account.name)
                   $subscriptionId
  Tenant         : $tenantId
  Resource group : $ResourceGroup ($location), holding $existing resources
  Repository     : $GithubOwner/$GithubRepo  (branch: $GithubBranch)
  Identity       : $identityName

  The identity will be granted Contributor and Role Based Access Control
  Administrator ON THIS RESOURCE GROUP ONLY. Inside the group it can create, change
  and delete anything, and grant roles. Outside it, it can see nothing at all.

  Anyone who can merge to $GithubBranch in that repository can use it, so the
  group should hold nothing you would mind losing.

"@

if (($existing -as [int]) -gt 0 -and $env:I_KNOW_THE_GROUP_IS_NOT_EMPTY -ne 'yes') {
    Write-Host @"
  ----------------------------------------------------------------------
  REFUSING TO CONTINUE: $ResourceGroup already holds $existing
  resources. A group dedicated to this demo should start empty.

  See what is in it:

      az resource list --resource-group $ResourceGroup -o table

  Use an empty group, or override if those resources are yours:

      `$env:I_KNOW_THE_GROUP_IS_NOT_EMPTY = 'yes'
      ./scripts/bootstrap-azure.ps1
  ----------------------------------------------------------------------

"@
    Write-Host 'Aborted.'
    exit 1
}

if ((Read-Host 'Continue? [y/N]') -notin @('y', 'Y')) {
    Write-Host 'Aborted.'
    return
}

Write-Host "==> Managed identity $identityName"
az identity create --name $identityName --resource-group $ResourceGroup --location $location `
    --tags workload=$Workload purpose='Temporary CI/CD demo' managedBy='bootstrap script' `
    --output none

$identity    = az identity show --name $identityName --resource-group $ResourceGroup | ConvertFrom-Json
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
        --resource-group $ResourceGroup `
        --issuer 'https://token.actions.githubusercontent.com' `
        --subject $Subject `
        --audiences 'api://AzureADTokenExchange' `
        --output none
}

# Do not construct the subject by hand. GitHub now pins it to immutable numeric owner
# and repository IDs, so it reads "repo:owner@107984787/name@1382946058" rather than
# "repo:owner/name". Guessing wrong produces AADSTS700213 at the first deploy, with a
# message that looks like a configuration mistake somewhere else entirely.
$subjectPrefix = $null
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $subjectPrefix = gh api "repos/$GithubOwner/$GithubRepo/actions/oidc/customization/sub" `
        --jq .sub_claim_prefix 2>$null
    if ($LASTEXITCODE -ne 0) { $subjectPrefix = $null }
}

if ($subjectPrefix) {
    Write-Host '==> Subject prefix, read from GitHub:'
    Write-Host "    $subjectPrefix"
}
else {
    $subjectPrefix = "repo:$GithubOwner/$GithubRepo"
    Write-Host '==> Could not ask GitHub for the subject prefix; assuming the older form:'
    Write-Host "    $subjectPrefix"
    Write-Host '    If the first deploy fails with AADSTS700213, read the real one with:'
    Write-Host "      gh api repos/$GithubOwner/$GithubRepo/actions/oidc/customization/sub --jq .sub_claim_prefix"
}

Add-FederatedCredential -Name "github-$GithubBranch" `
    -Subject "${subjectPrefix}:ref:refs/heads/$GithubBranch"

# Lets pull requests preview infrastructure changes with what-if. Pull requests from
# forks cannot use it: GitHub withholds id-token: write from them, so they never get
# a token to present in the first place.
Add-FederatedCredential -Name 'github-pull-request' `
    -Subject "${subjectPrefix}:pull_request"

# Contributor alone is NOT enough: its notActions exclude Microsoft.Authorization/*/Write,
# so it cannot create the role assignment that main.bicep makes for the app-deploy
# identity. Role Based Access Control Administrator supplies exactly that, and is
# narrower than User Access Administrator.
function Add-ResourceGroupRole {
    param([string]$RoleId, [string]$Label)

    Write-Host "==> Role assignment on ${ResourceGroup}: $Label"
    # Tolerate "already assigned" on a rerun, but let every other failure reach the
    # trap. Swallowing errors here would hide exactly the policy denials and
    # authorization failures this script most often hits. $LASTEXITCODE is checked
    # explicitly because whether a failing native command throws depends on the
    # PowerShell version.
    $stderr = az role assignment create `
        --assignee-object-id $principalId `
        --assignee-principal-type ServicePrincipal `
        --role $RoleId `
        --scope $rgScope `
        --output none 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ("$stderr" -match 'RoleAssignmentExists|already exists') {
            Write-Host '    (already assigned)'
        }
        else {
            throw "$stderr"
        }
    }
}

Add-ResourceGroupRole -RoleId $contributorRole -Label 'Contributor'
Add-ResourceGroupRole -RoleId $rbacAdminRole   -Label 'Role Based Access Control Administrator'

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

  Check what the identity may do, and where:

    az role assignment list --assignee $clientId --all -o table

  The Bicep needs the same subject prefix. Confirm it matches infra/main.dev.bicepparam:

    param githubSubjectPrefix = '$subjectPrefix'

  Next: deploy the infrastructure into $ResourceGroup, then record
  AZURE_WEBAPP_NAME and AZURE_DEPLOY_CLIENT_ID. See docs/00-azure-setup.md.

"@

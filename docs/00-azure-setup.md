# Azure setup

One-time work. After this, everything is created by pipelines.

Nothing in this repository stores an Azure password, key or certificate. Both pipelines
authenticate with short-lived tokens. This document explains how that trust is
established, and why it is built the way it is.

## The two identities

A single identity for everything would be simpler and wrong. The two pipelines need very
different power, so they get different identities:

| | `id-usndevops-iac` | `id-usndevops-dev-deploy` |
| --- | --- | --- |
| Used by | `infra-deploy.yml` | `app-deploy-oidc.yml` |
| Created by | `scripts/bootstrap-azure.sh` (by hand, once) | `infra/modules/deploy-identity.bicep` (by the pipeline) |
| Roles | Contributor + Role Based Access Control Administrator | Website Contributor |
| Scope | The whole subscription | One resource group |
| Why so broad | It creates resource groups and role assignments, which are subscription-level operations | It only pushes code into an app that already exists |

That asymmetry is worth saying out loud during the lecture. "Least privilege" does not mean
every identity is small; it means every identity is *as small as its job allows*. The
infrastructure pipeline's job is genuinely large, so the honest answer is to keep it
separate, use it rarely, and never give it to the app pipeline.

### Why a managed identity and not an app registration

Most guides tell you to create an Entra **app registration** (a "service principal") and
put a federated credential on it. That works, but it needs permission to write to the
Entra directory, and plenty of tenants forbid that. The USN tenant is one of them:

```bash
az rest --method GET --url "https://graph.microsoft.com/v1.0/policies/authorizationPolicy" \
  --query "defaultUserRolePermissions.allowedToCreateApps"
# false
```

A **user-assigned managed identity** takes the same federated credentials but is an
ordinary Azure resource on the Resource Manager plane. Owner on a subscription is enough,
no directory rights required. It also shows up in the resource group, gets tagged, and is
deleted along with everything else — which an app registration does not.

## Step 1 — pick a subscription

Use a sandbox. The bootstrap grants subscription-wide Contributor, which does not belong
in a shared or customer subscription.

```bash
az login
az account set --subscription "<your sandbox subscription>"
az account show --output table
```

## Step 2 — run the bootstrap

```bash
./scripts/bootstrap-azure.sh
```

PowerShell:

```powershell
./scripts/bootstrap-azure.ps1
```

It creates `rg-usndevops-identity`, the `id-usndevops-iac` identity, two federated
credentials, and two subscription-scope role assignments. It prints the three values you
need next and asks for confirmation before changing anything.

### What a federated credential actually is

There is no secret involved. GitHub signs a token describing the run, and Entra ID trusts
it only if the **subject** matches exactly:

```
repo:TobiasGunther/DevOps-Cloud-CI-CD-Demo:ref:refs/heads/main
```

A different branch, a fork, or another repository produces a different subject and is
refused. The trust is in *who is running the job*, not in a password someone copied.

## Step 3 — record the identifiers in GitHub

These are IDs, not credentials. They identify the identity; they do not authenticate as
it. Store them as **variables**, not secrets — so the Secrets page stays visibly empty.

```bash
gh variable set AZURE_IAC_CLIENT_ID   --body "<clientId from the script>"
gh variable set AZURE_TENANT_ID       --body "<tenantId>"
gh variable set AZURE_SUBSCRIPTION_ID --body "<subscriptionId>"
```

## Step 4 — deploy the infrastructure

```bash
gh workflow run "Infra - deploy to Azure"
gh run watch
```

The run summary prints the resource group, the web app name and URL, and the client ID of
the **app-deploy** identity that the Bicep just created. Record the last two:

```bash
gh variable set AZURE_WEBAPP_NAME       --body "<webAppName from the summary>"
gh variable set AZURE_DEPLOY_CLIENT_ID  --body "<deployIdentityClientId from the summary>"
```

## Step 5 — the publish profile, for the insecure demo only

This is the thing the lecture argues against, so create it deliberately and delete it
afterwards.

Azure disables SCM basic authentication on new apps by default, which is why
`infra/modules/webapp.bicep` switches it back on with `enableScmBasicAuth`. Without that,
no publish profile password exists at all.

```bash
az webapp deployment list-publishing-profiles \
  --name "<webAppName>" \
  --resource-group "rg-usndevops-dev" \
  --xml > publish-profile.xml

gh secret set AZURE_WEBAPP_PUBLISH_PROFILE < publish-profile.xml
rm publish-profile.xml   # do not leave it on disk
```

Open the XML before deleting it. The `userPWD` attribute is a working password in clear
text, and showing it on screen is the single most effective moment of the demo.

## Verifying the result

```bash
# The app-deploy identity should hold exactly one role, on one resource group.
az role assignment list --assignee "<deployIdentityClientId>" --all -o table

# The federated trust, and the branch it is bound to.
az identity federated-credential list \
  --identity-name "id-usndevops-dev-deploy" \
  --resource-group "rg-usndevops-dev" \
  --query "[].{name:name, subject:subject}" -o table
```

## Tearing it down

```bash
az group delete --name rg-usndevops-dev      --yes --no-wait
az group delete --name rg-usndevops-identity --yes --no-wait
```

Deleting the identity resource group revokes both pipelines at once. There is no secret
left behind at GitHub to worry about, except the publish profile — delete that too:

```bash
gh secret delete AZURE_WEBAPP_PUBLISH_PROFILE
```

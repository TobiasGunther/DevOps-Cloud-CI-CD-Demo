# Azure setup

One-time work. After this, everything is created by pipelines.

Nothing in this repository stores an Azure password, key or certificate. Both pipelines
authenticate with short-lived tokens. This document explains how that trust is
established, and why it is built the way it is.

## Everything lives in one resource group

`rg-devops-demo-dev` holds the lot: the web app, its plan, the logs, and both
identities. Nothing in this setup is granted at subscription scope, which means it can
run in a subscription where you are trusted with a single resource group and nothing
more — the common case at work, and the same boundary the lecture argues for on slide 31.

The resource group itself is the one thing you create by hand. Creating a resource group
is a subscription-level write, and needing that right back would defeat the point.

## The two identities

A single identity for everything would be simpler and wrong. The two pipelines need very
different power, so they get different identities:

| | `id-devops-demo-iac` | `id-devops-demo-dev-deploy` |
| --- | --- | --- |
| Used by | `infra-deploy.yml` | `app-deploy-oidc.yml` |
| Created by | `scripts/bootstrap-azure.sh` (by hand, once) | `infra/modules/deploy-identity.bicep` (by the pipeline) |
| Roles | Contributor + Role Based Access Control Administrator | Website Contributor |
| Can | Create, change and delete anything in the group, and grant roles in it | Push code into an app that already exists |
| Scope | `rg-devops-demo-dev` | `rg-devops-demo-dev` |

Same scope, very different power. That is the honest shape of least privilege: you rarely
get every identity down to nothing, but you can keep the powerful one rare, separate, and
boxed into a blast radius you are willing to lose. Worth saying out loud during the
lecture, because the alternative — one identity that does everything — is what most
projects actually have.

### Why a managed identity and not an app registration

Most guides tell you to create an Entra **app registration** (a "service principal") and
put a federated credential on it. That works, but it needs permission to write to the
Entra directory, and plenty of tenants forbid that. Check before you rely on it:

```bash
az rest --method GET --url "https://graph.microsoft.com/v1.0/policies/authorizationPolicy" \
  --query "defaultUserRolePermissions.allowedToCreateApps"
# false  -> ordinary users cannot create app registrations in this tenant
```

The call itself may be refused by a Conditional Access policy, in which case you cannot
even find out. Either way the answer is the same: do not build on an app registration.

A **user-assigned managed identity** takes the same federated credentials but is an
ordinary Azure resource on the Resource Manager plane. Rights on a resource group are
enough, no directory rights required. It also shows up in the group, gets tagged, and is
deleted along with everything else — which an app registration does not.

## Step 1 — sign in with MFA

```bash
az login --scope https://management.azure.com//.default
az account set --subscription "<your subscription>"
az account show --output table
```

The `--scope` is not decoration. Many tenants assign the built-in policy **Multi Factor
Authentication Enforcement - Write**, which denies every resource *create* and *update*
when the caller's token was issued without MFA. Reads keep working, so everything looks
fine right up until the first write fails:

```
RequestDisallowedByPolicy: Resource 'rg-devops-demo-dev' was disallowed by policy.
```

A cached single-sign-on token often lacks the MFA claim. Requesting a token for
Azure Resource Manager explicitly forces a fresh sign-in, which triggers the MFA
challenge. If it still fails, `az logout` first.

Worth knowing: that policy only applies when the caller is a **user**. Its rule tests
`requestContext().identity.idtyp == 'user'`, and managed identities present `app`. So it
constrains this one-time manual step and never the pipelines created below.

On Windows, run the scripts from Git Bash, WSL or Cloud Shell. They set
`MSYS_NO_PATHCONV` internally, because Git Bash otherwise rewrites `/subscriptions/<guid>`
into a Windows path and ARM answers with a misleading `MissingSubscription` that looks
like a permissions problem.

## Step 2 — create the resource group

The one manual resource. Everything else is created by code.

```bash
az group create --name rg-devops-demo-dev --location norwayeast
```

You need **Owner** on it, or **Contributor plus User Access Administrator**. Both parts
matter and the second is easy to miss: User Access Administrator grants
`Microsoft.Authorization/*` but no resource write at all, so on its own it can assign
roles and create nothing.

If someone else administers the subscription, ask them for the group and for Owner on it.
That is a far smaller request than subscription-wide rights, and it is the whole reason
this setup is scoped the way it is.

## Step 3 — run the bootstrap

```bash
./scripts/bootstrap-azure.sh
```

PowerShell:

```powershell
./scripts/bootstrap-azure.ps1
```

It creates the `id-devops-demo-iac` identity inside the group, two federated credentials,
and two role assignments **on the group**. It prints the three values you need next and
asks for confirmation before changing anything.

It also refuses to run against a group that already holds resources, since a group shared
with real work is the wrong blast radius for an identity a public repository can deploy
with. Override only if those resources are yours:

```bash
I_KNOW_THE_GROUP_IS_NOT_EMPTY=yes ./scripts/bootstrap-azure.sh
```

### What a federated credential actually is

There is no secret involved. GitHub signs a token describing the run, and Entra ID trusts
it only if the **subject** matches exactly:

```
repo:TobiasGunther/DevOps-Cloud-CI-CD-Demo:ref:refs/heads/main
```

A different branch, a fork, or another repository produces a different subject and is
refused. The trust is in *who is running the job*, not in a password someone copied.

## Step 4 — record the identifiers in GitHub

These are IDs, not credentials. They identify the identity; they do not authenticate as
it. Store them as **variables**, not secrets — so the Secrets page stays visibly empty.

```bash
gh variable set AZURE_IAC_CLIENT_ID   --body "<clientId from the script>"
gh variable set AZURE_TENANT_ID       --body "<tenantId>"
gh variable set AZURE_SUBSCRIPTION_ID --body "<subscriptionId>"
```

## Step 5 — deploy the infrastructure

The workflows are not on GitHub until you push, and two of the variables below come out of
this deployment, so run it locally the first time:

```bash
az deployment group create   --resource-group rg-devops-demo-dev   --parameters infra/main.dev.bicepparam   --name infra-bootstrap
```

Afterwards the pipeline does exactly the same thing on every push to `main`:

```bash
gh workflow run "Infra - deploy to Azure"
gh run watch
```

Either way you get the web app name and URL and the client ID of the **app-deploy**
identity the Bicep just created. Record the two you need:

```bash
gh variable set AZURE_WEBAPP_NAME --body "$(az deployment group show   --resource-group rg-devops-demo-dev --name infra-bootstrap   --query properties.outputs.webAppName.value -o tsv)"

gh variable set AZURE_DEPLOY_CLIENT_ID --body "$(az deployment group show   --resource-group rg-devops-demo-dev --name infra-bootstrap   --query properties.outputs.deployIdentityClientId.value -o tsv)"
```

## Step 6 — the publish profile, for the insecure demo only

This is the thing the lecture argues against, so create it deliberately and delete it
afterwards.

Azure disables SCM basic authentication on new apps by default, which is why
`infra/modules/webapp.bicep` switches it back on with `enableScmBasicAuth`. Without that,
no publish profile password exists at all.

```bash
az webapp deployment list-publishing-profiles \
  --name "<webAppName>" \
  --resource-group "rg-devops-demo-dev" \
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
  --identity-name "id-devops-demo-dev-deploy" \
  --resource-group "rg-devops-demo-dev" \
  --query "[].{name:name, subject:subject}" -o table
```

## Tearing it down

```bash
az group delete --name rg-devops-demo-dev --yes --no-wait
```

One group holds everything, so deleting it revokes both pipelines and removes every
resource in a single step. There is no secret left behind at GitHub to worry about, except
the publish profile — delete that too:

```bash
gh secret delete AZURE_WEBAPP_PUBLISH_PROFILE
```

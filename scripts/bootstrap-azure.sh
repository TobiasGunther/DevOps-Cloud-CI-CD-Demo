#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# One-time bootstrap: create the identity the INFRASTRUCTURE pipeline uses.
#
# Everything else in this repository is created by that pipeline. This script
# exists only to break the chicken-and-egg problem: something has to create the
# first identity, and it cannot be the pipeline that needs it.
#
# What it creates:
#   1. A small resource group to hold the identity itself
#   2. A user-assigned managed identity  (NOT an Entra app registration - see below)
#   3. Two federated credentials: one for main, one for pull requests
#   4. Two role assignments at subscription scope
#
# Why a managed identity rather than an app registration:
#   An app registration lives in the Entra directory, and many tenants forbid
#   ordinary users from creating one. A user-assigned managed identity is an
#   ordinary Azure resource on the ARM control plane, so Owner on a subscription
#   is enough. It supports the same federated credentials.
#
# Requires: Owner on the target subscription (or Contributor + RBAC Administrator).
# Run in Azure Cloud Shell, WSL, or any bash with the Azure CLI and gh installed.
# -----------------------------------------------------------------------------
set -euo pipefail

# ---- settings ---------------------------------------------------------------
WORKLOAD="${WORKLOAD:-devops-demo}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOCATION="${LOCATION:-norwayeast}"
GITHUB_OWNER="${GITHUB_OWNER:-TobiasGunther}"
GITHUB_REPO="${GITHUB_REPO:-DevOps-Cloud-CI-CD-Demo}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

IDENTITY_RG="rg-${WORKLOAD}-identity"
IDENTITY_NAME="id-${WORKLOAD}-iac"

# Verified against learn.microsoft.com/azure/role-based-access-control/built-in-roles
CONTRIBUTOR_ROLE="b24988ac-6180-42a0-ab88-20f7382dd24c"
RBAC_ADMIN_ROLE="f58310d9-a9f6-439a-9e8d-f62e7b41a168"

# ---- preflight --------------------------------------------------------------
command -v az >/dev/null || { echo "Azure CLI not found."; exit 1; }

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

cat <<EOF

  Subscription : ${SUBSCRIPTION_NAME}
                 ${SUBSCRIPTION_ID}
  Tenant       : ${TENANT_ID}
  Repository   : ${GITHUB_OWNER}/${GITHUB_REPO}  (branch: ${GITHUB_BRANCH})
  Identity     : ${IDENTITY_NAME} in ${IDENTITY_RG} (${LOCATION})

  This grants the identity Contributor and Role Based Access Control Administrator
  over the WHOLE subscription, because it has to create resource groups and role
  assignments. Use a sandbox subscription, never a shared or production one.

EOF
read -r -p "Continue? [y/N] " reply
[ "${reply}" = "y" ] || [ "${reply}" = "Y" ] || { echo "Aborted."; exit 0; }

# ---- 1. resource group for the identity -------------------------------------
echo "==> Resource group ${IDENTITY_RG}"
az group create --name "${IDENTITY_RG}" --location "${LOCATION}" \
  --tags workload="${WORKLOAD}" purpose="Temporary CI/CD demo" managedBy="bootstrap script" \
  --output none

# ---- 2. the identity --------------------------------------------------------
echo "==> Managed identity ${IDENTITY_NAME}"
az identity create --name "${IDENTITY_NAME}" --resource-group "${IDENTITY_RG}" \
  --location "${LOCATION}" --output none

CLIENT_ID=$(az identity show --name "${IDENTITY_NAME}" --resource-group "${IDENTITY_RG}" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show --name "${IDENTITY_NAME}" --resource-group "${IDENTITY_RG}" --query principalId -o tsv)

# ---- 3. federated credentials ----------------------------------------------
# The "subject" is the security boundary. GitHub signs a token describing the run;
# Entra ID issues an access token only when the subject matches one of these exactly.
# A fork, another branch, or another repository produces a different subject.
add_credential() {
  local name="$1" subject="$2"
  echo "==> Federated credential ${name}"
  echo "    subject: ${subject}"
  az identity federated-credential create \
    --name "${name}" \
    --identity-name "${IDENTITY_NAME}" \
    --resource-group "${IDENTITY_RG}" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "${subject}" \
    --audiences "api://AzureADTokenExchange" \
    --output none
}

add_credential "github-${GITHUB_BRANCH}" \
  "repo:${GITHUB_OWNER}/${GITHUB_REPO}:ref:refs/heads/${GITHUB_BRANCH}"

# Lets pull requests run what-if against the real subscription without being able
# to merge anything. Read the scope carefully before enabling this on a real system.
add_credential "github-pull-request" \
  "repo:${GITHUB_OWNER}/${GITHUB_REPO}:pull_request"

# ---- 4. role assignments ----------------------------------------------------
# Contributor alone is NOT enough: its notActions exclude Microsoft.Authorization/*/Write,
# so it cannot create the role assignment that main.bicep makes for the app-deploy
# identity. Role Based Access Control Administrator supplies exactly that, and is
# narrower than User Access Administrator.
assign_role() {
  local role="$1" label="$2"
  echo "==> Role assignment: ${label}"
  az role assignment create \
    --assignee-object-id "${PRINCIPAL_ID}" \
    --assignee-principal-type ServicePrincipal \
    --role "${role}" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}" \
    --output none
}

assign_role "${CONTRIBUTOR_ROLE}" "Contributor (subscription)"
assign_role "${RBAC_ADMIN_ROLE}"  "Role Based Access Control Administrator (subscription)"

# ---- 5. report --------------------------------------------------------------
cat <<EOF

  Done. None of the values below are secrets: they identify the identity, they do
  not authenticate as it. Store them as repository VARIABLES, not secrets.

    AZURE_IAC_CLIENT_ID    ${CLIENT_ID}
    AZURE_TENANT_ID        ${TENANT_ID}
    AZURE_SUBSCRIPTION_ID  ${SUBSCRIPTION_ID}

  With the GitHub CLI:

    gh variable set AZURE_IAC_CLIENT_ID   --body "${CLIENT_ID}"
    gh variable set AZURE_TENANT_ID       --body "${TENANT_ID}"
    gh variable set AZURE_SUBSCRIPTION_ID --body "${SUBSCRIPTION_ID}"

  Next: run the "Infra - deploy to Azure" workflow, then follow docs/00-azure-setup.md
  to record AZURE_WEBAPP_NAME and AZURE_DEPLOY_CLIENT_ID from its output.

EOF

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

# Without this, a failing az command exits the script instantly. If the script was
# started by double-clicking it, the window closes with it and the error is gone
# before anyone can read it. Explain what happened and hold the window open.
on_error() {
  local exit_code=$? line=$1
  echo
  echo "  --------------------------------------------------------------------"
  echo "  Stopped at line ${line} (exit ${exit_code}). The Azure CLI error is"
  echo "  printed above this box."
  echo
  echo "  Two failures are common here:"
  echo
  echo "  RequestDisallowedByPolicy, mentioning multi-factor authentication"
  echo "      Your Azure token was issued without MFA, and this tenant denies"
  echo "      resource writes from such tokens. Sign in again and rerun:"
  echo
  echo "          az logout"
  echo "          az login --scope https://management.azure.com//.default"
  echo
  echo "  AuthorizationFailed"
  echo "      The account lacks Owner, or Contributor plus Role Based Access"
  echo "      Control Administrator, on this subscription. Check with:"
  echo
  echo "          az account show --output table"
  echo
  echo "  Nothing is left half-built: rerunning is safe, every step is idempotent."
  echo "  --------------------------------------------------------------------"
  echo
  # Only pause when someone is actually watching; never hang a CI run.
  if [ -t 0 ]; then
    read -r -p "  Press Enter to close. " _ || true
  fi
  exit "${exit_code}"
}
trap 'on_error ${LINENO}' ERR

# Git Bash on Windows rewrites arguments that look like Unix absolute paths, so
# "--scope /subscriptions/<guid>" arrives as "C:/Program Files/Git/subscriptions/<guid>"
# and ARM rejects it with a baffling "MissingSubscription" that reads like a
# permissions problem. These variables are ignored on Linux and macOS.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

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

# "Use a sandbox" is easy to agree with and easy to skip past. Show what is actually
# in the subscription, because a real sandbox is nearly empty and anything else is
# somebody's working environment.
RG_COUNT=$(az group list --query "length(@)" -o tsv 2>/dev/null || echo "?")
RESOURCE_COUNT=$(az resource list --query "length(@)" -o tsv 2>/dev/null || echo "?")

RISK=""
case "${SUBSCRIPTION_NAME}" in
  *prod*|*Prod*|*PROD*) RISK="its name contains \"prod\"" ;;
esac
if [ -z "${RISK}" ] && [ "${RESOURCE_COUNT}" != "?" ] && [ "${RESOURCE_COUNT}" -gt 20 ]; then
  RISK="it already holds ${RESOURCE_COUNT} resources, so it is not an empty sandbox"
fi

cat <<EOF

  Subscription : ${SUBSCRIPTION_NAME}
                 ${SUBSCRIPTION_ID}
  Tenant       : ${TENANT_ID}
  Contains     : ${RESOURCE_COUNT} resources in ${RG_COUNT} resource groups
  Repository   : ${GITHUB_OWNER}/${GITHUB_REPO}  (branch: ${GITHUB_BRANCH})
  Identity     : ${IDENTITY_NAME} in ${IDENTITY_RG} (${LOCATION})

  This grants the identity Contributor and Role Based Access Control Administrator
  over the WHOLE subscription, because it has to create resource groups and role
  assignments. Anyone able to merge to ${GITHUB_BRANCH} then controls this
  subscription, and Role Based Access Control Administrator lets the identity grant
  any role to anyone. Use a sandbox, never a shared or production subscription.

EOF

if [ -n "${RISK}" ]; then
  cat <<EOF
  ----------------------------------------------------------------------
  REFUSING TO CONTINUE BY DEFAULT: this does not look like a sandbox,
  because ${RISK}.

  If you are certain, rerun with:

      I_KNOW_THIS_IS_NOT_A_SANDBOX=yes ./scripts/bootstrap-azure.sh

  Otherwise switch subscription first:

      az account set --subscription "<sandbox>"
  ----------------------------------------------------------------------

EOF
  if [ "${I_KNOW_THIS_IS_NOT_A_SANDBOX:-}" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi
  echo "  Override set. Continuing against a non-sandbox subscription."
  echo
fi

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
  local role="$1" label="$2" err
  echo "==> Role assignment: ${label}"
  # Tolerate "already assigned" on a rerun, but let every other failure through to
  # the ERR trap. Swallowing errors here would hide exactly the policy denial and
  # authorization failures this script most often hits.
  if ! err=$(az role assignment create \
    --assignee-object-id "${PRINCIPAL_ID}" \
    --assignee-principal-type ServicePrincipal \
    --role "${role}" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}" \
    --output none 2>&1); then
    case "${err}" in
      *RoleAssignmentExists*|*already\ exists*)
        echo "    (already assigned)" ;;
      *)
        printf '%s\n' "${err}" >&2
        return 1 ;;
    esac
  fi
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

#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# One-time bootstrap: create the identity the INFRASTRUCTURE pipeline uses.
#
# Everything else in this repository is created by that pipeline. This script exists
# only to break the chicken-and-egg problem: something has to create the first
# identity, and it cannot be the pipeline that needs it.
#
# Everything lives in ONE resource group, which you create beforehand:
#
#     az group create --name rg-devops-demo-dev --location norwayeast
#
# and on which you need Owner, or Contributor plus User Access Administrator.
# Nothing here touches the subscription, so this works in a subscription where you
# are trusted with a single resource group and nothing more.
#
# What it creates, all inside that group:
#   1. A user-assigned managed identity  (NOT an Entra app registration - see below)
#   2. Two federated credentials: one for main, one for pull requests
#   3. Two role assignments, scoped to the group and nothing wider
#
# Why a managed identity rather than an app registration:
#   An app registration lives in the Entra directory, and many tenants forbid
#   ordinary users from creating one. A user-assigned managed identity is an
#   ordinary Azure resource on the ARM control plane, so rights on a resource group
#   are enough. It supports the same federated credentials.
#
# Run in Azure Cloud Shell, WSL, or any bash with the Azure CLI installed.
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
  echo "  Three failures are common here:"
  echo
  echo "  RequestDisallowedByPolicy, mentioning multi-factor authentication"
  echo "      Your Azure token was issued without MFA, and some tenants deny"
  echo "      resource writes from such tokens. Sign in again and rerun:"
  echo
  echo "          az logout"
  echo "          az login --scope https://management.azure.com//.default"
  echo
  echo "  AuthorizationFailed on a role assignment"
  echo "      You can create resources in the group but not grant roles in it."
  echo "      Ask for Owner, or User Access Administrator alongside Contributor,"
  echo "      on ${RESOURCE_GROUP:-the resource group}."
  echo
  echo "  MissingSubscription"
  echo "      Git Bash rewrote a /subscriptions/... argument into a Windows path."
  echo "      This script sets MSYS_NO_PATHCONV to prevent that; if you are running"
  echo "      the commands by hand, set it too."
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
GITHUB_OWNER="${GITHUB_OWNER:-TobiasGunther}"
GITHUB_REPO="${GITHUB_REPO:-DevOps-Cloud-CI-CD-Demo}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${WORKLOAD}-${ENVIRONMENT}}"
IDENTITY_NAME="id-${WORKLOAD}-iac"

# Verified against learn.microsoft.com/azure/role-based-access-control/built-in-roles
CONTRIBUTOR_ROLE="b24988ac-6180-42a0-ab88-20f7382dd24c"
RBAC_ADMIN_ROLE="f58310d9-a9f6-439a-9e8d-f62e7b41a168"

# ---- preflight --------------------------------------------------------------
command -v az >/dev/null || { echo "Azure CLI not found."; exit 1; }

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

RG_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

# The resource group is a prerequisite, not something this script creates. Creating
# one needs subscription rights, which is precisely what this design avoids needing.
if ! LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv 2>/dev/null); then
  cat <<EOF

  Resource group "${RESOURCE_GROUP}" does not exist in ${SUBSCRIPTION_NAME}.

  Create it, or ask whoever administers the subscription to:

      az group create --name ${RESOURCE_GROUP} --location norwayeast

  You then need Owner on it, or Contributor plus User Access Administrator.

EOF
  exit 1
fi

# This group is about to hold an identity a public repository can deploy with. If it
# already contains somebody else work, that is worth stopping over.
EXISTING=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo 0)

cat <<EOF

  Subscription   : ${SUBSCRIPTION_NAME}
                   ${SUBSCRIPTION_ID}
  Tenant         : ${TENANT_ID}
  Resource group : ${RESOURCE_GROUP} (${LOCATION}), holding ${EXISTING} resources
  Repository     : ${GITHUB_OWNER}/${GITHUB_REPO}  (branch: ${GITHUB_BRANCH})
  Identity       : ${IDENTITY_NAME}

  The identity will be granted Contributor and Role Based Access Control
  Administrator ON THIS RESOURCE GROUP ONLY. Inside the group it can create, change
  and delete anything, and grant roles. Outside it, it can see nothing at all.

  Anyone who can merge to ${GITHUB_BRANCH} in that repository can use it, so the
  group should hold nothing you would mind losing.

EOF

if [ "${EXISTING}" -gt 0 ] && [ "${I_KNOW_THE_GROUP_IS_NOT_EMPTY:-}" != "yes" ]; then
  cat <<EOF
  ----------------------------------------------------------------------
  REFUSING TO CONTINUE: ${RESOURCE_GROUP} already holds ${EXISTING}
  resources. A group dedicated to this demo should start empty.

  See what is in it:

      az resource list --resource-group ${RESOURCE_GROUP} -o table

  Use an empty group, or override if those resources are yours:

      I_KNOW_THE_GROUP_IS_NOT_EMPTY=yes ./scripts/bootstrap-azure.sh
  ----------------------------------------------------------------------

EOF
  echo "Aborted."
  exit 1
fi

read -r -p "Continue? [y/N] " reply
[ "${reply}" = "y" ] || [ "${reply}" = "Y" ] || { echo "Aborted."; exit 0; }

# ---- 1. the identity --------------------------------------------------------
echo "==> Managed identity ${IDENTITY_NAME}"
az identity create --name "${IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags workload="${WORKLOAD}" purpose="Temporary CI/CD demo" managedBy="bootstrap script" \
  --output none

CLIENT_ID=$(az identity show --name "${IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show --name "${IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" --query principalId -o tsv)

# ---- 2. federated credentials ----------------------------------------------
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
    --resource-group "${RESOURCE_GROUP}" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "${subject}" \
    --audiences "api://AzureADTokenExchange" \
    --output none
}

add_credential "github-${GITHUB_BRANCH}" \
  "repo:${GITHUB_OWNER}/${GITHUB_REPO}:ref:refs/heads/${GITHUB_BRANCH}"

# Lets pull requests preview infrastructure changes with what-if. Pull requests from
# forks cannot use it: GitHub withholds id-token: write from them, so they never get
# a token to present in the first place.
add_credential "github-pull-request" \
  "repo:${GITHUB_OWNER}/${GITHUB_REPO}:pull_request"

# ---- 3. role assignments, scoped to the group -------------------------------
# Contributor alone is NOT enough: its notActions exclude Microsoft.Authorization/*/Write,
# so it cannot create the role assignment that main.bicep makes for the app-deploy
# identity. Role Based Access Control Administrator supplies exactly that, and is
# narrower than User Access Administrator.
assign_role() {
  local role="$1" label="$2" err
  echo "==> Role assignment on ${RESOURCE_GROUP}: ${label}"
  # Tolerate "already assigned" on a rerun, but let every other failure through to
  # the ERR trap. Swallowing errors here would hide exactly the policy denials and
  # authorization failures this script most often hits.
  if ! err=$(az role assignment create \
    --assignee-object-id "${PRINCIPAL_ID}" \
    --assignee-principal-type ServicePrincipal \
    --role "${role}" \
    --scope "${RG_SCOPE}" \
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

assign_role "${CONTRIBUTOR_ROLE}" "Contributor"
assign_role "${RBAC_ADMIN_ROLE}"  "Role Based Access Control Administrator"

# ---- 4. report --------------------------------------------------------------
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

  Check what the identity may do, and where:

    az role assignment list --assignee ${CLIENT_ID} --all -o table

  Next: deploy the infrastructure into ${RESOURCE_GROUP}, then record
  AZURE_WEBAPP_NAME and AZURE_DEPLOY_CLIENT_ID. See docs/00-azure-setup.md.

EOF

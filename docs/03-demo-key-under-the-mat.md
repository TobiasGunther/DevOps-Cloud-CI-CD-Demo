# Demo 2 — "Nøkkelen under matta"

Slides 34–35. About 15 minutes.

Tell the audience what to look for before you switch screens:

1. Where the secret is, and what it actually grants
2. The federated trust, and which repository and branch it applies to
3. The role binding on the **resource group**, not the subscription
4. The workflow file without a single stored secret
5. That the app really does update when the deploy runs

The instruction that lands best: *watch for what is missing from the second file.*

## Before you start

```bash
gh secret list                  # exactly one entry
gh variable list                # five entries
az account show --output table  # correct directory
```

Tabs to have open: the repository's Settings → Secrets and variables page, the two
workflow files side by side, the Azure portal on the resource group, and `/swagger`.

Test the federated deploy the same day. This is the part that breaks.

## The run-through

### 1. The key under the mat (4 min)

Open **Settings → Secrets and variables → Actions**. One secret:
`AZURE_WEBAPP_PUBLISH_PROFILE`.

You cannot read it back — so show what it was. Open the publish profile you saved during
setup, or fetch a fresh one:

```bash
az webapp deployment list-publishing-profiles \
  --name "$AZURE_WEBAPP_NAME" --resource-group rg-devops-demo-dev --xml
```

Point at `userName` and `userPWD`. A working username and password, in clear text. Then
the four consequences from slide 30:

- it has left Azure and now lives at another vendor
- it grants everything on this app; there is no way to narrow it
- the Azure activity log will say the app was updated, not who updated it
- rotating it means changing it by hand everywhere, so in practice nobody does

The house-key-under-the-mat comparison works well here.

Now run it:

```bash
gh workflow run "App - deploy with publish profile (insecure)"
gh run watch
```

It works. That is the uncomfortable part, and worth saying plainly: this is how most
projects start, including professional ones.

### 2. A detail worth pausing on (1 min)

Azure now ships new web apps with SCM basic authentication **disabled**. This demo only
works because the infrastructure code deliberately turns it back on:

```bash
grep -A4 "resource scmBasicAuth" infra/modules/webapp.bicep
```

The vendor made the insecure option opt-in. That is the argument, made by Microsoft rather
than by you.

### 3. The trust, as code (4 min)

Open `infra/modules/deploy-identity.bicep` and read the three resources in order.

**The identity** — a user-assigned managed identity, not an app registration. Mention why:
in a locked-down tenant you usually cannot create an app registration, but you can create
this. It is also an ordinary resource, so it appears in the resource group and is deleted
with it.

**The federated credential** — the subject is the security boundary:

```
repo:TobiasGunther@107984787/DevOps-Cloud-CI-CD-Demo@1382946058:ref:refs/heads/main
```

One repository. One branch. A fork produces a different subject and is refused.

The numbers are GitHub's immutable owner and repository IDs, and they are worth a sentence:
names can be released and reclaimed, so trusting `owner/name` would let whoever claims the
name next inherit this access. Trusting the IDs does not. Show it live:

```bash
az identity federated-credential list \
  --identity-name id-devops-demo-dev-deploy \
  --resource-group rg-devops-demo-dev \
  --query "[].{name:name, subject:subject, issuer:issuer}" -o table
```

**The role assignment** — on the resource group, not the subscription:

```bash
az role assignment list --assignee "$AZURE_DEPLOY_CLIENT_ID" --all \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

One role, `Website Contributor`, one resource group. Everything else in the subscription is
invisible to it.

If you want to be scrupulous — and it is a good moment to be — note that `Website
Contributor` grants `Microsoft.Web/sites/*`, which technically includes re-enabling basic
auth. Built-in roles are coarser than you would like; a custom role is the next step. That
honesty lands better than pretending the boundary is perfect.

### 4. The file with nothing in it (3 min)

Put the two workflow files side by side. The build jobs are identical. Diff the rest:

```bash
diff .github/workflows/app-deploy-publish-profile.yml \
     .github/workflows/app-deploy-oidc.yml
```

One file passes `publish-profile: ${{ secrets.… }}`. The other signs in first and passes
nothing. The secure file references `vars`, never `secrets` — client ID, tenant ID and
subscription ID are identifiers, not credentials. They identify the identity; they do not
authenticate as it.

```bash
gh workflow run "App - deploy with federated identity (secure)"
gh run watch
```

The **Show what this identity is allowed to do** step prints the role assignment inside the
run, so the audience sees the boundary from the pipeline's own point of view.

### 5. The optional showstopper (2 min)

If time allows, this is the sharpest version of the whole demo. Flip one flag:

```bash
# in infra/main.dev.bicepparam
param enableScmBasicAuth = false
```

```bash
git commit -am "Turn off basic auth" && git push
gh workflow run "Infra - deploy to Azure" && gh run watch
```

Now rerun the publish-profile workflow. It fails with **401**. Rerun the federated one. It
succeeds. Same app, same environment, same code — one of them depended on something that
could be switched off, leaked, or rotated, and the other did not.

Remember to set it back to `true` afterwards if you plan to run the demo again.

## What to land at the end (slide 35)

- Both variants deployed the same app to the same environment
- The first left a long-lived secret with another vendor
- The second stored nothing and granted one role on one resource group
- The identity setup cost a few extra minutes once, and nothing afterwards
- You will meet this pattern everywhere two services talk to each other

## If something goes wrong

| Symptom | Cause |
| --- | --- |
| `AADSTS70021: No matching federated identity record found` | The subject does not match. You are on the wrong branch, or running from a fork. Compare the branch against the credential's subject. |
| `Error: Login failed` with no detail | `id-token: write` is missing from the workflow's `permissions:`. |
| Publish-profile deploy fails with 401 | SCM basic auth is off. Either intentional (step 5) or `enableScmBasicAuth` is `false`. |
| `AuthorizationFailed` on the app deploy | The role assignment has not replicated yet. It usually takes under a minute on first creation. |
| App returns 403 | F1 daily CPU quota exhausted. Switch to `B1` and rerun the infra workflow. |

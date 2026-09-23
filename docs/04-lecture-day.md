# Lecture day checklist

1 October 2026. The speaker notes on slides 16 and 34 ask for a pre-flight; this is it.

## The day before

```bash
# Everything green, app answering, correct commit live
cd app && dotnet test --nologo && cd ..
gh run list --limit 5
curl -s "https://$AZURE_WEBAPP_NAME.azurewebsites.net/api/info" | jq .
```

- [ ] Run **both** deploy workflows end to end. The federated one is what breaks; test it today, not tomorrow.
- [ ] Confirm branch protection is on and the required check name matches the job name (`Build and test`).
- [ ] Confirm the keep-warm workflow has run recently. GitHub disables scheduled workflows after 60 days of inactivity — check the Actions tab, not just the file.
- [ ] `./demo/break-it.sh status` reports **Correct**.
- [ ] Take fallback screenshots: the secrets page, the federated credential, the role assignment, a red PR, a successful run.
- [ ] Delete stray branches from rehearsals so the repository looks tidy on screen.

## Free tier: know the failure mode

The app runs on F1, which is free and has a hard limit: **60 CPU-minutes per day, shared
across every Free app in that region in the subscription**. When it runs out, Azure stops
the app and every request returns **HTTP 403 until midnight UTC**. There is no way to
reset it early.

Check on the morning:

```bash
az webapp show --name "$AZURE_WEBAPP_NAME" --resource-group rg-devops-demo-dev \
  --query "{state:state, availability:availabilityState}" -o table
```

If it is stopped, or if 403s appear mid-lecture, the escape hatch takes about a minute:

```bash
# infra/main.dev.bicepparam
param appServicePlanSku = 'B1'
```

```bash
gh workflow run "Infra - deploy to Azure" && gh run watch
```

B1 has no daily quota and keeps Always On. It costs roughly USD 0.45 per day. Scale back
to F1 or delete the resource group afterwards.

There is also no Always On on F1, so the app unloads after about 20 minutes idle and the
next request waits 20–30 seconds. The keep-warm workflow covers this, but hit the URL
yourself during the break as well.

## One hour before

- [ ] `az login` in the right directory; `az account show` on screen once so students see which subscription.
- [ ] `gh auth status` fine.
- [ ] Browser: large font, no private tabs, no unrelated bookmarks visible.
- [ ] Tabs open and logged in:
  - Actions tab of the repository
  - Settings → Secrets and variables
  - The two workflow files side by side
  - Azure portal on `rg-devops-demo-dev`
  - `https://<app>.azurewebsites.net/swagger`
- [ ] Warm the app: `curl -s https://<app>.azurewebsites.net/health`
- [ ] Terminal in the repository root, `main` branch, clean working tree.
- [ ] Agree with Martin who keeps time and who takes questions during the demos.

## The portal tour (slide 29)

Follow the slide's order rather than clicking around:

1. **Resource group** `rg-devops-demo-dev` — everything that shares a lifecycle, in one place
2. **App Service** — configuration, environment variables, which version is live
3. **Log Analytics / Application Insights** — logs and metrics; observability in practice
4. **Cost analysis** — what this costs per month, and set a budget alert live

Say out loud that AWS and Google Cloud have the same four things under different names.

## After the lecture

```bash
gh secret delete AZURE_WEBAPP_PUBLISH_PROFILE
az group delete --name rg-devops-demo-dev --yes --no-wait
```

Leaving the resource group running is exactly the mistake slide 25 warns about. Delete it
the same day, or at minimum scale back to F1 and set a budget alert.

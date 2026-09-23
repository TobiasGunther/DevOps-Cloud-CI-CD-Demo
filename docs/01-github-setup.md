# GitHub setup

## The repository must be public

Branch protection and rulesets are free on **public** repositories, and unavailable on
private repositories on the GitHub Free plan. Demo 1 depends on the merge button actually
being blocked, so on a private free repo the central beat of that demo silently does not
happen: the check still goes red, but merge stays available.

Public also means students can browse the repository afterwards, which slide 37 encourages.

```bash
gh repo edit --visibility public --accept-visibility-change-consequences
```

## Variables and secrets

The split is the point of demo 2. Everything the secure path needs is a **variable**;
the only **secret** in the repository exists to demonstrate the insecure path.

### Variables (not sensitive)

| Name | Used by | Where it comes from |
| --- | --- | --- |
| `AZURE_TENANT_ID` | both Azure workflows | `scripts/bootstrap-azure.sh` |
| `AZURE_SUBSCRIPTION_ID` | both Azure workflows | `scripts/bootstrap-azure.sh` |
| `AZURE_IAC_CLIENT_ID` | `infra-deploy.yml` | `scripts/bootstrap-azure.sh` |
| `AZURE_DEPLOY_CLIENT_ID` | `app-deploy-oidc.yml` | infra run summary |
| `AZURE_WEBAPP_NAME` | both app workflows, keep-warm | infra run summary |

```bash
gh variable list
```

### Secret (the one the lecture argues against)

| Name | Used by |
| --- | --- |
| `AZURE_WEBAPP_PUBLISH_PROFILE` | `app-deploy-publish-profile.yml` only |

```bash
gh secret list
```

Having exactly one secret, needed by exactly one workflow, makes the comparison concrete:
open the Secrets page on screen and there is a single entry, and it belongs to the file
you are about to argue against.

## Branch protection

This is what makes a red test block a merge. Without it the pipeline is advisory.

```bash
gh api -X PUT "repos/{owner}/{repo}/branches/main/protection" \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Build and test"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

Notes:

- `"Build and test"` is the **job name** from `ci.yml` (`jobs.build-and-test.name`), not
  the workflow name. If you rename the job, update this.
- `enforce_admins: false` is deliberate. You stay able to merge past a red check if
  something goes wrong live — and being honest about that with the students is a better
  lesson than pretending the rule is absolute. Mention that a real project would usually
  set it to `true`.
- A required check only appears in GitHub's picker after it has run at least once. Open
  one throwaway pull request before configuring this.
- `required_pull_request_reviews: null` means no second approver, because you are
  presenting alone. A real repository would require at least one.

Verify:

```bash
gh api "repos/{owner}/{repo}/branches/main/protection" \
  --jq '.required_status_checks.contexts'
```

## Environments

Both deploy workflows reference an environment named `dev`, which GitHub creates on first
use. It gives you a Deployments entry with a clickable URL, which is a nice thing to point
at after a deploy.

If you want the "approval before production" beat from slide 14 step 7, add a required
reviewer:

```bash
gh api -X PUT "repos/{owner}/{repo}/environments/dev" \
  -F "reviewers[][type]=User" \
  -F "reviewers[][id]=$(gh api user --jq .id)"
```

That pauses the deploy job until you click approve, live. Remove it afterwards or the
automatic deploy in demo 1 will stop being automatic.

## Actions permissions

Default settings are fine. Worth knowing:

- `permissions:` is declared per workflow in this repository rather than relying on the
  repository default, so each file states exactly what it needs.
- Only the OIDC workflows request `id-token: write`. The publish-profile workflow does not
  need it, because it does not prove who it is — it just presents a password.

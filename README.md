# Fra kode til produksjon — demo

Demo repository for the guest lecture *Objektorientert programmering 2* at USN,
1 October 2026, by Martin and Tobias (Egde).

A small .NET API, the infrastructure it runs on, and four pipelines — arranged so that two
live demos have something concrete to point at.

## What is here

```
app/            .NET 10 minimal API with Swagger, plus unit and integration tests
infra/          Bicep: resource group, App Service, monitoring, and the deploy identity
.github/        CI, infrastructure deploy, and two contrasting application deploys
scripts/        One-time Azure bootstrap (bash and PowerShell)
demo/           The prop that turns a pull request red on cue
docs/           Setup guides and a runbook per demo
```

## The application

Three endpoints, visible in Swagger UI at the root of the deployed app:

| Endpoint | What it is for |
| --- | --- |
| `GET /api/info` | Version and commit come from the **artifact**; environment and message come from **configuration**. Slide 27, made visible. |
| `GET /api/greet/{name}?language=nb\|en\|de` | Has real validation, so it has real tests. This is the one the red-test demo breaks. |
| `GET /api/principles` | The six DevOps principles from slide 10, served by the app the students watched deploy. |

`GET /health` backs the deploy smoke test and the keep-warm schedule.

```bash
cd app
dotnet test                                   # 22 tests, about a second
dotnet run --project src/DemoApi              # then open /swagger
```

## The pipelines

| Workflow | Trigger | Authentication | Point being made |
| --- | --- | --- | --- |
| `ci.yml` | pull request, push to main | none needed | A red test blocks the merge |
| `infra-deploy.yml` | `infra/**` changes, manual | federated identity | Infrastructure is code; pull requests preview it with what-if |
| `app-deploy-publish-profile.yml` | manual | **stored secret** | The key under the mat |
| `app-deploy-oidc.yml` | push to main, manual | **federated identity** | Same result, no secret |
| `keep-warm.yml` | schedule | none | Free tier insurance, not a teaching point |

Both application workflows build **once** and move a single artifact to the deploy job.
Their build jobs are identical on purpose — diff them and the only difference is how the
deploy authenticates. That diff is the lesson.

## Getting it running

1. [`docs/00-azure-setup.md`](docs/00-azure-setup.md) — the two identities, and why there are two
2. [`docs/01-github-setup.md`](docs/01-github-setup.md) — variables, the one secret, branch protection
3. [`docs/02-demo-red-test.md`](docs/02-demo-red-test.md) — runbook for demo 1
4. [`docs/03-demo-key-under-the-mat.md`](docs/03-demo-key-under-the-mat.md) — runbook for demo 2
5. [`docs/04-lecture-day.md`](docs/04-lecture-day.md) — pre-flight checks and fallbacks

## Two things worth knowing before you copy this

**The free tier can stop mid-demo.** F1 allows 60 CPU-minutes per day, shared across every
Free app in the region in that subscription. Past that, the app serves HTTP 403 until
midnight UTC. Switching `appServicePlanSku` to `B1` in `infra/main.dev.bicepparam` removes
the limit for about USD 0.45 a day. See [`docs/04-lecture-day.md`](docs/04-lecture-day.md).

**The insecure path is switched on deliberately.** Azure disables SCM basic authentication
on new web apps by default, so no publish profile password exists unless you ask for one.
`infra/modules/webapp.bicep` asks for one, via `enableScmBasicAuth`, purely so the demo has
something to argue against. Do not carry that flag into anything real.

## Tearing it down

```bash
az group delete --name rg-devops-demo-dev      --yes --no-wait
az group delete --name rg-devops-demo-identity --yes --no-wait
gh secret delete AZURE_WEBAPP_PUBLISH_PROFILE
```

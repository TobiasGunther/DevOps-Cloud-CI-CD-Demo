# Demo 1 — "Den røde testen"

Slides 16–17. About 10 minutes.

Tell the audience what to look for *before* you switch screens (slide 16 does this):

1. A pull request starts the build and the tests without anyone asking
2. A failing test makes the merge button unavailable — no discussion needed
3. The fix is pushed to the same branch and the pipeline reruns by itself
4. After merge, the same package goes out to the test environment
5. Nobody copies a file anywhere

## Before you start

```bash
./demo/break-it.sh status     # -> "Correct: tests should pass."
gh run list --limit 3         # last runs were green
curl -s https://<app>.azurewebsites.net/api/info | jq .commit
```

Have two browser tabs open: the repository's Actions tab, and the app's `/swagger` page.
Font size up, no private tabs visible.

## The run-through

### 1. Show the starting point (1 min)

Open `/api/info` on the deployed app and read out the `commit`. That number is what will
change at the end. Then show `app/tests/DemoApi.Tests/GreetingServiceTests.cs` briefly —
these are ordinary tests, nothing exotic.

### 2. Break something innocuous (2 min)

```bash
git switch -c fix/greeting-wording
./demo/break-it.sh break
git diff
```

The diff is one character: the comma disappears from `"Hei, {0}!"`. Say out loud that this
is the kind of change nobody reviews carefully — a copy tweak, obviously harmless.

```bash
git commit -am "Tidy up the Norwegian greeting"
git push -u origin fix/greeting-wording
gh pr create --fill
```

### 3. Watch it go red by itself (3 min)

Open the pull request. Nobody asked for anything, and the checks are already running.

```bash
gh pr checks --watch
```

When it fails, open the run. The summary table names the three failing tests, and the log
shows xUnit pointing at the exact character:

```
Expected: "Hei, Martin!"
Actual:   "Hei Martin!"
              ↑ (pos 3)
```

Then scroll to the merge box: **the merge button is unavailable**. Say clearly that this
is not magic — it is `docs/01-github-setup.md`, a rule the team chose and can change.

Worth noting: three tests failed from one character. You did not have to guess which ones.

### 4. Fix it and watch the rerun (2 min)

```bash
./demo/break-it.sh fix
git commit -am "Put the comma back"
git push
```

Say nothing for a moment and let them watch the checks start again on their own. This is
the feedback loop from slide 8, and it is worth letting the silence make the point.

### 5. Merge, and watch it deploy (2 min)

```bash
gh pr merge --squash --delete-branch
```

Merging to `main` starts `app-deploy-oidc.yml`. Point out the two jobs: **Build once**
produces an artifact, **Deploy** downloads that same artifact. Nothing is rebuilt between
environments — slide 27's rule, visible in the UI.

When it finishes, reload `/api/info`. The `commit` now matches the merge. That is the
whole loop, in about seven minutes.

## If something goes wrong

| Symptom | What to do |
| --- | --- |
| Checks do not start | Actions tab → check workflows are not disabled. Scheduled workflows get disabled after 60 days of no activity. |
| Merge button is available despite a red check | Branch protection is missing or the context name does not match the job name. See `docs/01-github-setup.md`. |
| App returns 403 | F1 daily CPU quota is exhausted; it resets at midnight UTC. Switch `appServicePlanSku` to `B1` in `infra/main.dev.bicepparam` and rerun the infra workflow. |
| Deploy succeeds but `/api/info` is unchanged | The smoke test would have failed. Hard-refresh; on F1 the app may be cold and take 20–30 seconds. |

Have screenshots of all five steps in a folder as a fallback, as the speaker notes suggest.

## Resetting afterwards

```bash
git switch main && git pull
./demo/break-it.sh status     # -> "Correct: tests should pass."
```

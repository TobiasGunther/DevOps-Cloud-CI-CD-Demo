using './main.bicep'

param workload = 'devops-demo'
param environmentName = 'dev'

// No location here on purpose: it defaults to the resource group's own location, so
// the resources cannot end up in a different region from the group that holds them.
// Override only if you deliberately want them apart.
// param location = 'norwayeast'

// Free. Capped at 60 CPU-minutes per day, per region, per subscription - and when the cap
// is reached the app is STOPPED and serves HTTP 403 until midnight UTC. There is no way to
// undo that mid-lecture. If the demo starts misbehaving on the day, switch to 'B1', rerun
// the infra workflow, and carry on: it takes about a minute and costs roughly USD 0.45/day.
param appServicePlanSku = 'F1'

// Read with:
//   gh api repos/TobiasGunther/DevOps-Cloud-CI-CD-Demo/actions/oidc/customization/sub --jq .sub_claim_prefix
// The numbers are GitHub's immutable owner and repository IDs. They are what make the
// trust survive a rename and refuse a recreated repository of the same name.
param githubSubjectPrefix = 'repo:TobiasGunther@107984787/DevOps-Cloud-CI-CD-Demo@1382946058'
param githubBranch = 'main'

// true  -> a publish profile exists, and workflow 3 (the insecure one) works.
// false -> no publish profile password exists; workflow 3 fails with 401 while workflow 4
//          keeps deploying happily. Flipping this live is the sharpest version of the demo.
param enableScmBasicAuth = true

param enableMonitoring = true

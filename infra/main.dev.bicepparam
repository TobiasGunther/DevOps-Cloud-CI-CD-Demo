using './main.bicep'

param workload = 'usndevops'
param environmentName = 'dev'
param location = 'westeurope'

// Free. Capped at 60 CPU-minutes per day, per region, per subscription - and when the cap
// is reached the app is STOPPED and serves HTTP 403 until midnight UTC. There is no way to
// undo that mid-lecture. If the demo starts misbehaving on the day, switch to 'B1', rerun
// the infra workflow, and carry on: it takes about a minute and costs roughly USD 0.45/day.
param appServicePlanSku = 'F1'

param githubOwner = 'TobiasGunther'
param githubRepo = 'DevOps-Cloud-CI-CD-Demo'
param githubBranch = 'main'

// true  -> a publish profile exists, and workflow 3 (the insecure one) works.
// false -> no publish profile password exists; workflow 3 fails with 401 while workflow 4
//          keeps deploying happily. Flipping this live is the sharpest version of the demo.
param enableScmBasicAuth = true

param enableMonitoring = true

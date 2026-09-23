<#
.SYNOPSIS
    Demo prop for "Den røde testen".

.DESCRIPTION
    Flips one character in the Norwegian greeting template: "Hei, {0}!" -> "Hei {0}!".
    It looks like a harmless copy tweak and it breaks three tests, which is exactly the
    point - you did not have to notice, the pipeline noticed.

.EXAMPLE
    ./demo/break-it.ps1 break
    ./demo/break-it.ps1 fix
    ./demo/break-it.ps1 status
#>
[CmdletBinding()]
param(
    [ValidateSet('break', 'fix', 'status')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Stop'

$file = Join-Path (Split-Path $PSScriptRoot -Parent) 'app/src/DemoApi/Features/Greeting.cs'
$good = '["nb"] = "Hei, {0}!",'
$bad  = '["nb"] = "Hei {0}!",'

$content = Get-Content -Path $file -Raw

switch ($Action) {
    'break' {
        # .Contains, not -like: the pattern holds [ and ] which -like treats as wildcards.
        if (-not $content.Contains($good)) { throw 'Already broken (or the file changed).' }
        # -Raw plus Replace keeps the file's existing line endings intact.
        [System.IO.File]::WriteAllText($file, $content.Replace($good, $bad))
        Write-Host 'Broken. Commit this on a branch, open a PR, and let CI go red.'
    }
    'fix' {
        if (-not $content.Contains($bad)) { throw 'Already correct.' }
        [System.IO.File]::WriteAllText($file, $content.Replace($bad, $good))
        Write-Host 'Fixed. Push to the same branch and watch the pipeline rerun by itself.'
    }
    'status' {
        if ($content.Contains($good))     { Write-Host 'Correct: tests should pass.' }
        elseif ($content.Contains($bad))  { Write-Host 'Broken: 3 tests should fail.' }
        else { throw 'Neither state found - has the file been edited?' }
    }
}

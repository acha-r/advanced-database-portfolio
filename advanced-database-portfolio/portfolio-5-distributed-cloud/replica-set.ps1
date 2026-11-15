# ROO's EMR: Portfolio 5 helper for a 3-node local MongoDB replica set
#
# Usage (PowerShell, from the folder holding this file):
#   .\replica-set.ps1 -Action init              # start all 3 nodes and initiate the replica set
#   .\replica-set.ps1 -Action stop  -Port 27018 # hard-stop one node (simulates a crash)
#   .\replica-set.ps1 -Action start -Port 27018 # bring that node back
#   .\replica-set.ps1 -Action list              # show which mongod nodes are running
#
# Nodes run on ports 27018, 27019 and 27020, so they do not clash with the MongoDB
# service on 27017. Data and logs go under C:\mongo-rs (not in the git repo).
# Needs mongod.exe (MongoDB Community Server) and mongosh on the PATH.

param(
  [Parameter(Mandatory = $true)][ValidateSet('init', 'start', 'stop', 'list')][string]$Action,
  [int]$Port = 0,
  [string]$Root = 'C:\mongo-rs'
)

$ports = 27018, 27019, 27020
$mongod = (Get-ChildItem 'C:\Program Files\MongoDB\Server\*\bin\mongod.exe' -ErrorAction SilentlyContinue |
  Sort-Object FullName -Descending | Select-Object -First 1).FullName
if (-not $mongod) { Write-Error 'mongod.exe not found under C:\Program Files\MongoDB\Server'; exit 1 }

function Start-Node([int]$p) {
  $dir = Join-Path $Root "node$p"
  New-Item -ItemType Directory -Force -Path (Join-Path $dir 'data') | Out-Null
  $dataDir = Join-Path $dir 'data'
  $logFile = Join-Path $dir 'mongod.log'
  $mongodArgs = @('--replSet', 'roos-rs', '--port', "$p", '--dbpath', $dataDir,
                  '--bind_ip', 'localhost', '--logpath', $logFile, '--oplogSize', '128')
  $proc = Start-Process -FilePath $mongod -ArgumentList $mongodArgs -WindowStyle Minimized -PassThru
  Start-Sleep -Seconds 2
  if ($proc.HasExited) {
    Write-Warning "node on port $p exited straight away (exit code $($proc.ExitCode)). See $logFile"
  } else {
    Write-Host "started node on port $p (pid $($proc.Id))"
  }
}

function Stop-Node([int]$p) {
  $procs = Get-CimInstance Win32_Process -Filter "Name='mongod.exe'" |
    Where-Object { $_.CommandLine -match "--port $p( |$)" }
  if (-not $procs) { Write-Host "no node found on port $p"; return }
  $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Write-Host "stopped node on port $p"
}

switch ($Action) {
  'init' {
    $ports | ForEach-Object { Start-Node $_ }
    Start-Sleep -Seconds 6
    $js = Join-Path $Root 'init.js'
    @"
rs.initiate({
  _id: 'roos-rs',
  members: [
    { _id: 0, host: 'localhost:27018' },
    { _id: 1, host: 'localhost:27019' },
    { _id: 2, host: 'localhost:27020' }
  ]
});
"@ | Set-Content -Path $js
    mongosh --port 27018 --quiet --file $js
  }
  'start' { if ($Port -eq 0) { Write-Error 'Give -Port'; exit 1 }; Start-Node $Port }
  'stop'  { if ($Port -eq 0) { Write-Error 'Give -Port'; exit 1 }; Stop-Node $Port }
  'list'  {
    Get-CimInstance Win32_Process -Filter "Name='mongod.exe'" |
      ForEach-Object { $_.CommandLine -replace '^.*(--port \d+).*$', '$1' }
  }
}
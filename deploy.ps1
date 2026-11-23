param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9.-]+$')][string]$Board)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$report=Get-Content -Raw -LiteralPath (Join-Path $root 'build-report.json') | ConvertFrom-Json
$manifest=Get-Content -Raw -LiteralPath (Join-Path $root 'build-manifest.json') | ConvertFrom-Json
if(-not $report.timing_ok){throw 'Timing did not pass. Build before deployment.'}
$bit=Join-Path $root ('orphan_kas/'+$manifest.bitstream)
if((Get-FileHash -LiteralPath $bit).Hash.ToLower() -ne $manifest.sha256){throw 'Bitstream hash mismatch'}
foreach($source in $manifest.sources.PSObject.Properties){
 $sourcePath=Join-Path $root ('orphan_kas/'+$source.Name)
 if($manifest.source_hash_format -eq 'sha256-lf'){
  $sourceText=[IO.File]::ReadAllText($sourcePath).Replace("`r`n","`n")
  $sourceSha=[Security.Cryptography.SHA256]::Create()
  try{$actual=[BitConverter]::ToString($sourceSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sourceText))).Replace('-','').ToLowerInvariant()}finally{$sourceSha.Dispose()}
 }else{$actual=(Get-FileHash -LiteralPath $sourcePath).Hash.ToLowerInvariant()}
 if($actual -ne $source.Value){throw ('Rebuild after source change: '+$source.Name)}
}
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
$bundle=Join-Path $env:TEMP ('orphan-kas-'+[guid]::NewGuid().ToString()+'.tar.gz')
try{
 & tar -czf $bundle --exclude=__pycache__ --exclude='*.local.json' --exclude='.settings-*' -C $root orphan_kas
 if($LASTEXITCODE){throw 'Packaging failed'}
 & scp -o BatchMode=yes $bundle ('root@'+$Board+':/tmp/orphan-kas-deploy.tar.gz')
 if($LASTEXITCODE){throw 'Upload failed'}
 $remote='set -e; systemctl stop s9-ledring 2>/dev/null || true; ardzy stop; tar -xzf /tmp/orphan-kas-deploy.tar.gz -C /opt/ardzy/projects; if command -v gcc >/dev/null; then cd /opt/ardzy/projects/orphan_kas; gcc -O3 -ffp-contract=off -fPIC -shared matrix_native.c -o matrix_native.so -lm; fi; ardzy load orphan_kas; sleep 3; ardzy status; ardzy log | tail -5'
 & ssh -o BatchMode=yes ('root@'+$Board) $remote
 if($LASTEXITCODE){throw 'Deployment failed. Existing projects remain available with ardzy load.'}
}finally{if(Test-Path -LiteralPath $bundle){Remove-Item -LiteralPath $bundle}}

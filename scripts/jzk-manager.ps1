param(
  [ValidateSet('Inventory','Finalize','Open','Backup','Update','RemovePlan','Remove')]
  [string]$Action = 'Inventory',
  [string]$TargetName,
  [string]$EnrichmentPath,
  [string[]]$Roots,
  [string]$DataRoot,
  [switch]$BackupFirst,
  [string]$ConfirmToken
)

$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:SkillRoot = Split-Path -Parent $PSScriptRoot
if (-not $DataRoot) { $DataRoot = Join-Path $env:LOCALAPPDATA 'JZK-Skills-Manager' }
$script:DataRoot = [IO.Path]::GetFullPath($DataRoot)
$script:DataDir = Join-Path $script:DataRoot 'data'
$script:HistoryDir = Join-Path $script:DataDir 'history'
$script:ReportDir = Join-Path $script:DataRoot 'reports\current'
$script:BackupDir = Join-Path $script:DataRoot 'backups'
$script:PlanDir = Join-Path $script:DataRoot 'plans'
@($script:DataDir,$script:HistoryDir,$script:ReportDir,$script:BackupDir,$script:PlanDir) | ForEach-Object { [IO.Directory]::CreateDirectory($_) | Out-Null }

function Write-Utf8([string]$Path,[string]$Text) {
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
  [IO.File]::WriteAllText($Path,$Text,$script:Utf8)
}
function Write-Json([string]$Path,$Value) { Write-Utf8 $Path ($Value | ConvertTo-Json -Depth 12) }
function Read-Json([string]$Path) { if (Test-Path -LiteralPath $Path) { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }; return $null }
function IsoNow { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz') }
function Safe-Name([string]$Name) { ($Name -replace '[\\/:*?"<>|]','_').Trim() }
function Hash-File([string]$Path) {
  $sha=[Security.Cryptography.SHA256]::Create(); try { $stream=[IO.File]::OpenRead($Path); try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() } finally { $stream.Dispose() } } finally { $sha.Dispose() }
}
function Get-SkillName([string]$Manifest,[string]$Directory) {
  $head = Get-Content -LiteralPath $Manifest -Encoding UTF8 -TotalCount 30
  foreach($line in $head){ if($line -match '^name\s*:\s*["'']?(.+?)["'']?\s*$'){ return $matches[1].Trim() } }
  return (Split-Path -Leaf $Directory)
}
function Get-Description([string]$Manifest) {
  $head = Get-Content -LiteralPath $Manifest -Encoding UTF8 -TotalCount 50
  foreach($line in $head){ if($line -match '^description\s*:\s*["'']?(.+?)["'']?\s*$'){ return $matches[1].Trim() } }
  return ''
}
function Get-RepoInfo([string]$Start) {
  $cursor=[IO.DirectoryInfo]::new($Start); $repo=$null
  while($cursor){ if(Test-Path -LiteralPath (Join-Path $cursor.FullName '.git')){$repo=$cursor.FullName;break}; $cursor=$cursor.Parent }
  if(-not $repo){ return [ordered]@{repoRoot=$null;githubUrl=$null;repoOwner=$null;updateMode='none'} }
  if(-not (Get-Command git -ErrorAction SilentlyContinue)){ return [ordered]@{repoRoot=$repo;githubUrl=$null;repoOwner=$null;updateMode='none'} }
  $remote = (& git -C $repo config --get remote.origin.url 2>$null | Select-Object -First 1)
  $url=$null;$owner=$null
  if($remote -match 'github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?$'){ $owner=$matches[1];$url="https://github.com/$($matches[1])/$($matches[2] -replace '\.git$','')" }
  [ordered]@{repoRoot=$repo;githubUrl=$url;repoOwner=$owner;updateMode=if($url){'direct'}else{'none'}}
}
function Source-Label([string]$Path) {
  $p=$Path.ToLowerInvariant(); if($p -like '*\.codex\plugins\*'){return 'Codex 插件'}; if($p -like '*\.codex\skills\*'){return 'Codex Skill'}; if($p -like '*\.agents\skills\*'){return 'Agents Skill'}; return '本地发现'
}
function Default-Roots {
  @((Join-Path $env:USERPROFILE '.codex\skills'),(Join-Path $env:USERPROFILE '.agents\skills'),(Join-Path $env:USERPROFILE '.codex\plugins\cache'),(Join-Path $env:USERPROFILE 'Desktop')) | Where-Object { Test-Path -LiteralPath $_ }
}
function To-Map($Items,[string]$Key) { $m=@{}; foreach($i in @($Items)){ if($null -ne $i -and $i.$Key){$m[[string]$i.$Key]=$i} }; $m }
function Copy-Property($From,$To,[string]$Name,$Default=$null) { if($From -and $From.PSObject.Properties.Name -contains $Name){$To[$Name]=$From.$Name}else{$To[$Name]=$Default} }
function Resolve-Record([string]$Name) {
  $latest=Read-Json (Join-Path $script:DataDir 'latest.json'); if(-not $latest){throw '尚无缓存，请先执行分析。'}
  $hits=@($latest.records | Where-Object { $_.name -eq $Name -or $_.directory -eq $Name -or $_.manifestPath -eq $Name })
  if($hits.Count -eq 0){throw "没有找到目标：$Name"}; if($hits.Count -gt 1){throw "名称不唯一，请改用完整路径：$Name"}; $hits[0]
}
function Assert-SafeTarget([string]$Directory) {
  $full=[IO.Path]::GetFullPath($Directory).TrimEnd('\'); $forbidden=@([IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\'),[IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex\skills')).TrimEnd('\'),[IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.agents\skills')).TrimEnd('\'),$script:DataRoot.TrimEnd('\'))
  if($forbidden -contains $full){throw "拒绝操作顶层目录：$full"}; if(-not (Test-Path -LiteralPath $full -PathType Container)){throw "目录不存在：$full"}; return $full
}
function Backup-Directory([string]$Directory,[string]$Name) {
  $full=Assert-SafeTarget $Directory; $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'; $zip=Join-Path $script:BackupDir ("{0}-{1}.zip" -f (Safe-Name $Name),$stamp)
  Compress-Archive -LiteralPath $full -DestinationPath $zip -CompressionLevel Optimal; return $zip
}

if($Action -eq 'Inventory'){
  if(-not $Roots -or $Roots.Count -eq 0){$Roots=Default-Roots}
  $latest=Read-Json (Join-Path $script:DataDir 'latest.json'); $old=To-Map @($latest.records) 'manifestPath'; $seen=@{};$records=@();$pending=@()
  foreach($root in $Roots){
    if(-not (Test-Path -LiteralPath $root)){continue}
    foreach($file in Get-ChildItem -LiteralPath $root -Filter 'SKILL.md' -File -Recurse -ErrorAction SilentlyContinue){
      $manifest=$file.FullName; if($seen.ContainsKey($manifest)){continue};$seen[$manifest]=$true;$dir=$file.Directory.FullName;$name=Get-SkillName $manifest $dir
      $isTarget=(-not $TargetName -or $name -eq $TargetName -or $dir -eq $TargetName -or $manifest -eq $TargetName)
      $hash=Hash-File $manifest;$repo=Get-RepoInfo $dir;$prev=$old[$manifest];$changed=($isTarget -and (-not $prev -or $prev.contentHash -ne $hash -or $TargetName))
      $r=[ordered]@{name=$name;manifestPath=$manifest;directory=$dir;description=Get-Description $manifest;sourceLabel=Source-Label $manifest;createdAt=$file.Directory.CreationTime.ToString('yyyy-MM-dd HH:mm');contentHash=$hash;status='active';firstMissingAt=$null;repoRoot=$repo.repoRoot;githubUrl=$repo.githubUrl;repoOwner=$repo.repoOwner;updateMode=$repo.updateMode;changed=$changed}
      $records += [pscustomobject]$r; if($changed){$pending += [pscustomobject]@{name=$name;manifestPath=$manifest;directory=$dir;description=$r.description;previousSummary=if($prev){$prev.summaryZh}else{$null};previousCategory=if($prev){$prev.category}else{$null}}}
    }
  }
  if($latest -and -not $TargetName){foreach($prev in @($latest.records)){if($prev -and -not $seen.ContainsKey([string]$prev.manifestPath)){ $missing=if($prev.firstMissingAt){$prev.firstMissingAt}else{IsoNow};$r=[ordered]@{};foreach($p in $prev.PSObject.Properties){$r[$p.Name]=$p.Value};$r.status='inactive';$r.firstMissingAt=$missing;$r.changed=$false;$records += [pscustomobject]$r }}}
  $payload=[ordered]@{scannedAt=IsoNow;targetName=$TargetName;roots=@($Roots);records=@($records);pending=@($pending);stats=[ordered]@{scanned=@($records|Where-Object status -eq 'active').Count;pending=$pending.Count;cached=@($records|Where-Object {$_.status -eq 'active' -and -not $_.changed}).Count;inactive=@($records|Where-Object status -eq 'inactive').Count}}
  $path=Join-Path $script:DataDir 'inventory.json';Write-Json $path $payload;[pscustomobject]@{ok=$true;inventoryPath=$path;pendingCount=$pending.Count;stats=$payload.stats}|ConvertTo-Json -Depth 5;exit
}

if($Action -eq 'Finalize'){
  $inventory=Read-Json (Join-Path $script:DataDir 'inventory.json');if(-not $inventory){throw '缺少 inventory.json，请先执行 Inventory。'}
  $latest=Read-Json (Join-Path $script:DataDir 'latest.json');$old=To-Map @($latest.records) 'manifestPath';$enriched=@();if($EnrichmentPath){$enriched=@(Read-Json ([IO.Path]::GetFullPath($EnrichmentPath)))};$new=To-Map $enriched 'path';$records=@()
  foreach($item in @($inventory.records)){
    $prev=$old[[string]$item.manifestPath];$fresh=$new[[string]$item.manifestPath];$r=[ordered]@{}
    foreach($p in $item.PSObject.Properties){if($p.Name -ne 'changed'){$r[$p.Name]=$p.Value}}
    $defaultSummary=$item.description;$defaultCategory='待分类';$defaultFunctions=@();$defaultOverlaps=@();$defaultDifference=''
    if($prev){$defaultSummary=$prev.summaryZh;$defaultCategory=$prev.category;$defaultFunctions=@($prev.functions);$defaultOverlaps=@($prev.overlaps);$defaultDifference=$prev.difference}
    Copy-Property $fresh $r 'summaryZh' $defaultSummary;Copy-Property $fresh $r 'category' $defaultCategory;Copy-Property $fresh $r 'functions' $defaultFunctions;Copy-Property $fresh $r 'overlaps' $defaultOverlaps;Copy-Property $fresh $r 'difference' $defaultDifference;$records += [pscustomobject]$r
  }
  $generated=IsoNow;$result=[ordered]@{schemaVersion=1;generatedAt=$generated;records=@($records);stats=[ordered]@{total=$records.Count;overlap=@($records|Where-Object {@($_.overlaps).Count -gt 0}).Count;inactive=@($records|Where-Object status -eq 'inactive').Count}}
  $latestPath=Join-Path $script:DataDir 'latest.json';Write-Json $latestPath $result;$history=Join-Path $script:HistoryDir ((Get-Date -Format 'yyyyMMdd-HHmmss')+'.json');Write-Json $history $result
  Copy-Item -LiteralPath (Join-Path $script:SkillRoot 'report\index.html') -Destination (Join-Path $script:ReportDir 'index.html') -Force
  $compact=$result|ConvertTo-Json -Depth 12 -Compress;Write-Utf8 (Join-Path $script:ReportDir 'catalog.js') ('window.JZK_DATA = '+$compact+';')
  [pscustomobject]@{ok=$true;reportPath=(Join-Path $script:ReportDir 'index.html');latestPath=$latestPath;historyPath=$history;stats=$result.stats}|ConvertTo-Json -Depth 5;exit
}

if($Action -eq 'Open'){
  $report=Join-Path $script:ReportDir 'index.html';if(-not (Test-Path -LiteralPath $report)){throw '尚无报告，请先执行完整分析。'};Start-Process $report;[pscustomobject]@{ok=$true;reportPath=$report}|ConvertTo-Json;exit
}

if($Action -eq 'Backup'){
  if(-not $TargetName){throw 'Backup 需要 TargetName。'};$r=Resolve-Record $TargetName;$zip=Backup-Directory $r.directory $r.name;[pscustomobject]@{ok=$true;backupPath=$zip}|ConvertTo-Json;exit
}

if($Action -eq 'Update'){
  if(-not $TargetName){throw 'Update 需要 TargetName。'};$r=Resolve-Record $TargetName;if($r.status -ne 'active' -or $r.updateMode -ne 'direct' -or -not $r.repoRoot){throw '该项目不满足自动更新条件。'}
  $p=$r.manifestPath.ToLowerInvariant();if($p -notlike '*\.codex\skills\*' -and $p -notlike '*\.agents\skills\*' -and $p -notlike '*\.codex\plugins\*'){throw '仅自动更新已经安装到 Codex/Agents 的项目。'}
  $dirty=& git -C $r.repoRoot status --porcelain;if($dirty){throw '仓库存在未提交改动，已停止更新。'};$backup=$null;if($BackupFirst){$backup=Backup-Directory $r.repoRoot $r.name}
  & git -C $r.repoRoot pull --ff-only;if($LASTEXITCODE -ne 0){throw 'git pull --ff-only 失败。'};[pscustomobject]@{ok=$true;name=$r.name;repoRoot=$r.repoRoot;backupPath=$backup}|ConvertTo-Json;exit
}

if($Action -eq 'RemovePlan'){
  if(-not $TargetName){throw 'RemovePlan 需要 TargetName。'};$r=Resolve-Record $TargetName;$target=Assert-SafeTarget $r.directory;$affected=@(Get-ChildItem -LiteralPath $target -Filter 'SKILL.md' -File -Recurse | ForEach-Object {Get-SkillName $_.FullName $_.Directory.FullName});$token=[guid]::NewGuid().ToString('N');$plan=[ordered]@{token=$token;createdAt=IsoNow;target=$target;name=$r.name;affectedSkills=$affected};$planPath=Join-Path $script:PlanDir ($token+'.json');Write-Json $planPath $plan;[pscustomobject]@{ok=$true;confirmToken=$token;target=$target;affectedSkills=$affected;requiresExplicitConfirmation=$true}|ConvertTo-Json -Depth 5;exit
}

if($Action -eq 'Remove'){
  if(-not $ConfirmToken -or $ConfirmToken -notmatch '^[a-f0-9]{32}$'){throw '需要 RemovePlan 返回的确认令牌。'};$planPath=Join-Path $script:PlanDir ($ConfirmToken+'.json');$plan=Read-Json $planPath;if(-not $plan){throw '确认令牌无效或已使用。'};$target=Assert-SafeTarget $plan.target
  Add-Type -AssemblyName Microsoft.VisualBasic;[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($target,'OnlyErrorDialogs','SendToRecycleBin');Remove-Item -LiteralPath $planPath -Force;[pscustomobject]@{ok=$true;movedToRecycleBin=$target;affectedSkills=$plan.affectedSkills}|ConvertTo-Json -Depth 5;exit
}

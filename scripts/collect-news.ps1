<#
  collect-news.ps1
  전날 오후 ~ 당일(실행시각)까지의 기사를 수집해 JSON으로 저장한다.

  수집 경로
    A. 연합뉴스 최신뉴스 목록 (1~21p)  - 원문링크 + 정확한 시각 + 리드문. 키 불필요.
    B. 연합뉴스 카테고리 RSS            - 최근 몇 시간 보강. 키 불필요.
    C. 네이버 검색 API (선택)          - 24시간 전체 구간 커버. config\naver-api.json 필요.
                                         없으면 자동으로 건너뛴다(A+B만으로도 동작).

  사용:
    powershell -ExecutionPolicy Bypass -File collect-news.ps1
    powershell -ExecutionPolicy Bypass -File collect-news.ps1 -SinceHour 12
#>
[CmdletBinding()]
param(
  [int]$SinceHour = 12,          # 창 시작: 전날 이 시각부터
  [string]$OutDir,
  [string]$ConfigDir,
  [int]$YnaMaxPage = 21
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
if (-not $OutDir)    { $OutDir    = Join-Path $scriptRoot '..\data' }
if (-not $ConfigDir) { $ConfigDir = Join-Path $scriptRoot '..\config' }

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

$now         = Get-Date
$windowStart = (Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $SinceHour -Minute 0 -Second 0).AddDays(-1)
$windowEnd   = $now

Write-Host ("[window] {0:yyyy-MM-dd HH:mm} ~ {1:yyyy-MM-dd HH:mm}" -f $windowStart, $windowEnd)

function Get-Html {
  param([string]$Url, [string]$Referer = 'https://www.google.com/')
  $h = @{ 'User-Agent' = $UA; 'Referer' = $Referer; 'Accept-Language' = 'ko-KR,ko;q=0.9' }
  for ($try = 1; $try -le 3; $try++) {
    try { return (Invoke-WebRequest -Uri $Url -Headers $h -TimeoutSec 25 -UseBasicParsing).Content }
    catch {
      if ($try -eq 3) { Write-Host ("  ! fail {0} :: {1}" -f $Url, $_.Exception.Message.Split("`n")[0]); return $null }
      Start-Sleep -Milliseconds (700 * $try)
    }
  }
}

function Convert-Entity {
  param([string]$s)
  if (-not $s) { return '' }
  $s = [regex]::Replace($s, '<[^>]+>', '')
  $s = $s -replace '&#x27;', "'" -replace '&#39;', "'" -replace '&quot;', '"' `
          -replace '&lt;', '<' -replace '&gt;', '>' -replace '&nbsp;', ' ' -replace '&amp;', '&'
  return ($s -replace '\s+', ' ').Trim()
}

$items = New-Object System.Collections.ArrayList
function Add-Item {
  param($Title, $Url, $Summary, $Press, $Published, $Section, $Source)
  $t = Convert-Entity $Title
  if (-not $t -or -not $Url) { return }
  [void]$items.Add([pscustomobject]@{
    title = $t; url = $Url; summary = (Convert-Entity $Summary); press = $Press
    published = $Published; section = $Section; source = $Source
  })
}

# =============================================================== A. 연합뉴스 목록
Write-Host '[A] Yonhap latest list'
$stop = $false
for ($p = 1; $p -le $YnaMaxPage -and -not $stop; $p++) {
  $html = Get-Html "https://www.yna.co.kr/news/$p" 'https://www.yna.co.kr/news'
  if (-not $html) { continue }
  $blocks = [regex]::Matches($html, '(?s)<li data-cid="(AKR\d+)">.*?<span class="txt-time">([^<]*)</span>')
  if ($blocks.Count -eq 0) { break }

  $oldest = $null
  foreach ($b in $blocks) {
    $chunk = $b.Value
    $title = [regex]::Match($chunk, '(?s)<span class="title01">(.*?)</span>').Groups[1].Value
    $lead  = [regex]::Match($chunk, '(?s)<p class="lead">(.*?)</p>').Groups[1].Value

    $pub = $null
    $m = [regex]::Match($b.Groups[2].Value.Trim(), '^(\d{2})-(\d{2})\s+(\d{2}):(\d{2})$')
    if ($m.Success) {
      try {
        $pub = Get-Date -Year $now.Year -Month ([int]$m.Groups[1].Value) -Day ([int]$m.Groups[2].Value) `
                        -Hour ([int]$m.Groups[3].Value) -Minute ([int]$m.Groups[4].Value) -Second 0
      } catch { $pub = $null }
      if ($pub -and $pub -gt $now.AddDays(1)) { $pub = $pub.AddYears(-1) }
    }
    if (-not $pub) { continue }
    if ($null -eq $oldest -or $pub -lt $oldest) { $oldest = $pub }
    if ($pub -lt $windowStart -or $pub -gt $windowEnd) { continue }

    Add-Item -Title $title -Url ("https://www.yna.co.kr/view/" + $b.Groups[1].Value) -Summary $lead `
             -Press '연합뉴스' -Published $pub.ToString('yyyy-MM-dd HH:mm') -Section '최신' -Source 'yna-list'
  }
  if ($oldest -and $oldest -lt $windowStart) { $stop = $true }
  Start-Sleep -Milliseconds 150
}
Write-Host ("  -> {0} items so far" -f $items.Count)

# =============================================================== B. 연합뉴스 RSS
Write-Host '[B] Yonhap category RSS'
$rss = @{
  '정치' = 'politics'; '경제' = 'economy'; '산업' = 'industry'
  '사회' = 'society'; '국제' = 'international'; '지역' = 'local'; '주요' = 'news'
}
foreach ($k in $rss.Keys) {
  $x = Get-Html ("https://www.yna.co.kr/rss/{0}.xml" -f $rss[$k]) 'https://www.yna.co.kr/'
  if (-not $x) { continue }
  try { $doc = [xml]$x } catch { continue }
  foreach ($it in $doc.rss.channel.item) {
    $pub = $null
    try { $pub = [datetime]::Parse($it.pubDate) } catch { continue }
    if ($pub -lt $windowStart -or $pub -gt $windowEnd) { continue }
    $tt = $it.title;       if ($tt -isnot [string]) { $tt = $tt.InnerText }
    $dd = $it.description; if ($dd -isnot [string]) { $dd = $dd.InnerText }
    Add-Item -Title $tt -Url $it.link -Summary $dd -Press '연합뉴스' `
             -Published $pub.ToString('yyyy-MM-dd HH:mm') -Section $k -Source 'yna-rss'
  }
  Start-Sleep -Milliseconds 120
}
Write-Host ("  -> {0} items so far" -f $items.Count)

# =============================================================== C. 네이버 검색 API
$naverCfg = Join-Path $ConfigDir 'naver-api.json'
if (Test-Path $naverCfg) {
  Write-Host '[C] Naver Search API'
  $cfg = Get-Content $naverCfg -Raw -Encoding UTF8 | ConvertFrom-Json
  $nh = @{ 'X-Naver-Client-Id' = $cfg.client_id; 'X-Naver-Client-Secret' = $cfg.client_secret }

  $queries = @(
    @{ q = '속보';   sec = '속보' }, @{ q = '사건사고'; sec = '사건' }
    @{ q = '경찰';   sec = '사건' }, @{ q = '화재';     sec = '사건' }
    @{ q = '경제';   sec = '경제' }, @{ q = '증시';     sec = '경제' }
    @{ q = '환율';   sec = '경제' }, @{ q = '금리';     sec = '경제' }
    @{ q = '부동산'; sec = '경제' }, @{ q = '물가';     sec = '경제' }
    @{ q = '국제';   sec = '해외' }, @{ q = '외교';     sec = '해외' }
    @{ q = '미국';   sec = '해외' }, @{ q = '중국';     sec = '해외' }
    @{ q = '북한';   sec = '해외' }, @{ q = '정부';     sec = '정치' }
  )

  $apiFail = 0
  foreach ($qd in $queries) {
    $added = 0
    for ($start = 1; $start -le 901; $start += 100) {
      $u = 'https://openapi.naver.com/v1/search/news.json?query=' +
           [uri]::EscapeDataString($qd.q) + "&display=100&start=$start&sort=date"
      try {
        $r = Invoke-RestMethod -Uri $u -Headers $nh -TimeoutSec 25
      } catch {
        $apiFail++
        if ($apiFail -le 2) { Write-Host ("  ! API error ({0}): {1}" -f $qd.q, $_.Exception.Message.Split("`n")[0]) }
        break
      }
      if (-not $r.items -or $r.items.Count -eq 0) { break }

      $tooOld = $false
      foreach ($it in $r.items) {
        $pub = $null
        try { $pub = [datetime]::Parse($it.pubDate) } catch { continue }
        if ($pub -lt $windowStart) { $tooOld = $true; continue }
        if ($pub -gt $windowEnd) { continue }
        $link = $it.originallink
        if (-not $link) { $link = $it.link }
        Add-Item -Title $it.title -Url $link -Summary $it.description -Press '' `
                 -Published $pub.ToString('yyyy-MM-dd HH:mm') -Section $qd.sec -Source 'naver-api'
        $added++
      }
      if ($tooOld) { break }
      Start-Sleep -Milliseconds 120
    }
    Write-Host ("  {0,-8} +{1}" -f $qd.q, $added)
  }
} else {
  Write-Host ("[C] skipped - no {0}" -f $naverCfg)
  Write-Host '    (네이버 검색 API 키를 넣으면 24시간 전체 구간을 커버합니다)'
}

# =============================================================== 아카이브 누적
# 한 번 수집하면 최근 7~8시간치만 잡힌다. 실행할 때마다 아카이브에 합쳐 두면
# (예: 전날 저녁 + 당일 오후) 24시간 구간이 온전히 채워진다.
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$archiveFile = Join-Path $OutDir 'archive.json'

# 요약이 지나치게 길면 아카이브가 비대해지므로 잘라 둔다
foreach ($it in $items) {
  if ($it.summary -and $it.summary.Length -gt 700) { $it.summary = $it.summary.Substring(0, 700) }
}

$merged = @{}
if (Test-Path $archiveFile) {
  try {
    $old = Get-Content $archiveFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($it in $old.articles) { $merged[$it.url] = $it }
  } catch { Write-Host '  ! archive.json 읽기 실패 - 새로 만듭니다' }
}
$before = $merged.Count
# 같은 기사가 목록/RSS 양쪽에서 잡히면 더 긴 요약을 남긴다 (RSS description 은 잘려 있는 경우가 많다)
foreach ($it in $items) {
  if (-not $it.url) { continue }
  if ($merged.ContainsKey($it.url)) {
    $ex = $merged[$it.url]
    $exLen = 0; if ($ex.summary) { $exLen = $ex.summary.Length }
    $newLen = 0; if ($it.summary) { $newLen = $it.summary.Length }
    if ($newLen -gt $exLen) { $ex.summary = $it.summary }
    if (-not $ex.press -and $it.press) { $ex.press = $it.press }
  } else {
    $merged[$it.url] = $it
  }
}

# 창(약 26시간)보다 넉넉히 2일치만 남긴다 — 저장소 용량을 위해
$cutoff = $now.AddDays(-2)
$kept = New-Object System.Collections.ArrayList
foreach ($it in $merged.Values) {
  $p = $null
  try { $p = [datetime]::Parse($it.published) } catch { continue }
  if ($p -ge $cutoff) { [void]$kept.Add($it) }
}
$archive = @($kept | Sort-Object published -Descending)

[pscustomobject]@{
  updated_at = $now.ToString('yyyy-MM-dd HH:mm:ss')
  total      = $archive.Count
  articles   = $archive
} | ConvertTo-Json -Depth 6 | Out-File -FilePath $archiveFile -Encoding utf8

Write-Host ''
Write-Host ("[archive] {0} -> {1} articles (+{2} new)" -f $before, $archive.Count, ($archive.Count - $before))

# =============================================================== 창 필터 / 저장
$inWindow = $archive | Where-Object {
  $p = [datetime]::Parse($_.published); $p -ge $windowStart -and $p -le $windowEnd
}

$seen  = @{}
$final = New-Object System.Collections.ArrayList
foreach ($it in ($inWindow | Sort-Object published -Descending)) {
  $key = [regex]::Replace($it.title, '[^0-9A-Za-z가-힣]', '').ToLower()
  if ($key.Length -gt 40) { $key = $key.Substring(0, 40) }
  if (-not $key) { continue }
  if ($seen.ContainsKey($key)) { continue }
  $seen[$key] = $true
  [void]$final.Add($it)
}

$outFile = Join-Path $OutDir ("news-{0}.json" -f $now.ToString('yyyyMMdd'))

[pscustomobject]@{
  generated_at = $now.ToString('yyyy-MM-dd HH:mm:ss')
  window_start = $windowStart.ToString('yyyy-MM-dd HH:mm')
  window_end   = $windowEnd.ToString('yyyy-MM-dd HH:mm')
  total        = $final.Count
  articles     = $final
} | ConvertTo-Json -Depth 6 | Out-File -FilePath $outFile -Encoding utf8

Write-Host ''
Write-Host ("[done] {0} articles -> {1}" -f $final.Count, $outFile)
$final | Group-Object section | Sort-Object Count -Descending |
  ForEach-Object { Write-Host ("   {0,-8} {1}" -f $_.Name, $_.Count) }
$oldestAll = ($final | Sort-Object published | Select-Object -First 1).published
Write-Host ("   oldest: {0}" -f $oldestAll)

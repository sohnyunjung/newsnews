<#
  build-page.ps1
  digest\digests.json  ->  digest\index.html
  (Artifact 로 발행할 정적 페이지를 생성한다. doctype/html/head/body 는 발행 시 자동으로 감싸지므로 넣지 않는다.)
#>
[CmdletBinding()]
param(
  [string]$DigestDir,
  [string]$OutFile,
  # GitHub Pages 용 완전한 HTML 문서를 만든다 (Artifact 발행용은 조각만 필요)
  [switch]$Full
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
if (-not $DigestDir) { $DigestDir = Join-Path $scriptRoot '..\digest' }

$jsonPath = Join-Path $DigestDir 'digests.json'
if ($OutFile) { $outPath = $OutFile } else { $outPath = Join-Path $DigestDir 'index.html' }
if (-not (Test-Path $jsonPath)) { throw "not found: $jsonPath" }

$data = Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$days = @($data.days | Sort-Object date -Descending)

function E {
  param([string]$s)
  if ($null -eq $s) { return '' }
  return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}
function Fmt-Date {
  param([string]$d)
  $dt = [datetime]::ParseExact($d, 'yyyy-MM-dd', $null)
  return ("{0}년 {1}월 {2}일" -f $dt.Year, $dt.Month, $dt.Day)
}

$sb = New-Object System.Text.StringBuilder
function W { param([string]$s) [void]$sb.AppendLine($s) }

W '<title>놓치면 안 되는 속보</title>'
W '<link rel="preconnect" href="https://fonts.googleapis.com">'
W '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
W '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans+KR:wght@400;500;600&family=Noto+Serif+KR:wght@600;700&display=swap">'

W @'
<style>
:root{
  --bg:#EDEFF0; --surface:#FFFFFF; --ink:#151A1E; --muted:#5C6870;
  --line:#D3D9DC; --line-soft:#E4E8EA; --accent:#0E5B63; --signal:#A32E22;
  --sans:"IBM Plex Sans KR","Malgun Gothic",system-ui,sans-serif;
  --serif:"Noto Serif KR","Batang",Georgia,serif;
  --mono:"IBM Plex Mono",ui-monospace,Consolas,monospace;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --bg:#12161A; --surface:#191E23; --ink:#E5EAEC; --muted:#8B99A1;
    --line:#2A3238; --line-soft:#212930; --accent:#56B6BB; --signal:#E07A68;
  }
}
:root[data-theme="dark"]{
  --bg:#12161A; --surface:#191E23; --ink:#E5EAEC; --muted:#8B99A1;
  --line:#2A3238; --line-soft:#212930; --accent:#56B6BB; --signal:#E07A68;
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--bg); color:var(--ink);
  font-family:var(--sans); font-size:16px; line-height:1.6;
  -webkit-font-smoothing:antialiased;
  word-break:keep-all; overflow-wrap:break-word;
}
a{color:inherit}
.shell{max-width:880px; margin:0 auto; padding:0 24px}

/* ---------- masthead ---------- */
.masthead{border-bottom:2px solid var(--ink);
  padding:48px 0 18px; display:flex; align-items:flex-end; justify-content:space-between; gap:24px; flex-wrap:wrap}
.masthead h1{font-family:var(--serif); font-weight:700; font-size:34px; line-height:1.15;
  margin:0; letter-spacing:-.01em; text-wrap:balance}
.masthead .sub{font-family:var(--mono); font-size:11.5px; letter-spacing:.09em;
  text-transform:uppercase; color:var(--muted); margin-top:8px}
.masthead .meta{font-family:var(--mono); font-size:12px; color:var(--muted); text-align:right; line-height:1.7}

/* ---------- date tabs (top) ---------- */
.datebar{position:sticky; top:0; z-index:20; background:var(--bg);
  border-bottom:1px solid var(--line); display:flex; align-items:stretch; gap:16px}
.datebar .label{font-family:var(--mono); font-size:10.5px; letter-spacing:.12em;
  text-transform:uppercase; color:var(--muted); display:flex; align-items:center;
  padding-right:16px; border-right:1px solid var(--line-soft); flex:0 0 auto}
.datebar ol{list-style:none; margin:0; padding:0; display:flex; gap:2px;
  overflow-x:auto; scrollbar-width:thin}
.datebar li{flex:0 0 auto}
.datebar a{display:flex; align-items:baseline; gap:7px; padding:14px 14px 12px;
  text-decoration:none; color:var(--muted); font-family:var(--mono); font-size:13.5px;
  border-bottom:2px solid transparent; white-space:nowrap; transition:color .15s,border-color .15s}
.datebar a:hover{color:var(--ink)}
.datebar a .n{font-size:11px; opacity:.65}
.datebar a.on{color:var(--ink); border-bottom-color:var(--accent)}

/* ---------- day ---------- */
.day{padding:44px 0 8px; border-bottom:1px solid var(--line); scroll-margin-top:52px}
.day:last-of-type{border-bottom:0}
.dateline{display:flex; align-items:baseline; gap:14px; flex-wrap:wrap; margin-bottom:6px}
.dateline h2{font-family:var(--serif); font-weight:700; font-size:27px; margin:0; letter-spacing:-.01em}
.dateline .wd{font-family:var(--mono); font-size:13px; color:var(--muted)}
.daymeta{font-family:var(--mono); font-size:12px; color:var(--muted); margin-bottom:6px}
.daynote{font-size:13px; color:var(--muted); background:var(--surface);
  border-left:2px solid var(--accent); padding:9px 13px; margin:14px 0 0; border-radius:0 3px 3px 0}

/* ---------- group ---------- */
.group{margin-top:38px}
.grouphead{display:flex; align-items:center; gap:12px; margin-bottom:2px}
.grouphead .name{font-family:var(--mono); font-size:11.5px; font-weight:500;
  letter-spacing:.13em; text-transform:uppercase; color:var(--accent)}
.group[data-kind="속보"] .grouphead .name{color:var(--signal)}
.grouphead .rule{flex:1; height:1px; background:var(--line)}
.grouphead .cnt{font-family:var(--mono); font-size:11.5px; color:var(--muted)}

/* ---------- items ---------- */
.items{list-style:none; margin:0; padding:0}
.item{display:grid; grid-template-columns:74px minmax(0,1fr); gap:18px;
  padding:20px 0; border-bottom:1px solid var(--line-soft)}
.item:last-child{border-bottom:0}
.item .t{font-family:var(--mono); font-size:12.5px; color:var(--muted);
  font-variant-numeric:tabular-nums; padding-top:4px}
.group[data-kind="속보"] .item .t{color:var(--signal)}
.item h3{font-family:var(--serif); font-weight:600; font-size:18.5px; line-height:1.45;
  margin:0 0 7px; letter-spacing:-.005em; text-wrap:balance}
.item h3 a{text-decoration:none; background-image:linear-gradient(var(--accent),var(--accent));
  background-size:0% 1px; background-repeat:no-repeat; background-position:0 100%; transition:background-size .2s}
.item h3 a:hover,.item h3 a:focus-visible{color:var(--accent); background-size:100% 1px}
.item p{margin:0; font-size:15px; line-height:1.72; color:var(--ink); max-width:66ch}
.item .src{margin-top:9px; font-family:var(--mono); font-size:11.5px; color:var(--muted);
  display:flex; align-items:center; gap:8px; flex-wrap:wrap}
.item .src a{color:var(--muted); text-decoration:none; border-bottom:1px solid var(--line)}
.item .src a:hover,.item .src a:focus-visible{color:var(--accent); border-bottom-color:var(--accent)}
.item .src .dot{opacity:.45}

footer{border-top:2px solid var(--ink); margin-top:52px;
  padding:20px 0 56px; font-family:var(--mono); font-size:11.5px; color:var(--muted);
  display:flex; justify-content:space-between; gap:16px; flex-wrap:wrap}
a:focus-visible{outline:2px solid var(--accent); outline-offset:3px; border-radius:2px}

@media (max-width:720px){
  .shell{padding:0 18px}
  .masthead{padding:32px 0 14px}
  .masthead h1{font-size:26px}
  .masthead .meta{text-align:left}
  .datebar .label{display:none}
  .datebar a{padding:12px 11px 10px; font-size:13px}
  .dateline h2{font-size:23px}
  .item{grid-template-columns:minmax(0,1fr); gap:4px}
  .item .t{padding-top:0}
  .item h3{font-size:17px}
  .item p{font-size:14.5px}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important; animation:none!important}}
</style>
'@

# ------------------------------------------------------------------ masthead
$latest = $days[0]
$totalItems = 0
foreach ($d in $days) { foreach ($g in $d.groups) { $totalItems += @($g.items).Count } }

W '<div class="shell">'
W '<header class="masthead">'
W '  <div>'
W '    <h1>놓치면 안 되는 속보</h1>'
W '    <div class="sub">속보 · 사건사고 · 해외 · 경제 &nbsp;/&nbsp; 매일 14:00 갱신</div>'
W '  </div>'
W '  <div class="meta">'
W ("    최근 갱신 {0}<br>수록 {1}일 · 기사 {2}건" -f (E (Fmt-Date $latest.date)), $days.Count, $totalItems)
W '  </div>'
W '</header>'

# ------------------------------------------------------------------ date tabs
W '<nav class="datebar" aria-label="날짜 선택">'
W '  <span class="label">날짜</span>'
W '  <ol>'
$first = $true
foreach ($d in $days) {
  $n = 0; foreach ($g in $d.groups) { $n += @($g.items).Count }
  $dt = [datetime]::ParseExact($d.date, 'yyyy-MM-dd', $null)
  $cls = ''
  if ($first) { $cls = ' class="on"'; $first = $false }
  W ('    <li><a{0} href="#d{1}" data-d="{1}">{2}<span class="n">{3}</span></a></li>' -f `
      $cls, $d.date, $dt.ToString('M월 d일'), $n)
}
W '  </ol>'
W '</nav>'

# ------------------------------------------------------------------ days
W '<main>'
foreach ($d in $days) {
  $n = 0; foreach ($g in $d.groups) { $n += @($g.items).Count }
  W ('<section class="day" id="d{0}">' -f $d.date)
  W '  <div class="dateline">'
  W ('    <h2>{0}</h2>' -f (E (Fmt-Date $d.date)))
  if ($d.weekday) { W ('    <span class="wd">{0}요일</span>' -f (E $d.weekday)) }
  W '  </div>'
  $meta = ("수집 구간 {0}" -f (E $d.window))
  if ($d.pool) { $meta += ("  ·  후보 {0}건 중 {1}건 선별" -f $d.pool, $n) }
  W ('  <div class="daymeta">{0}</div>' -f $meta)
  if ($d.note) { W ('  <p class="daynote">{0}</p>' -f (E $d.note)) }

  foreach ($g in $d.groups) {
    $items = @($g.items)
    if ($items.Count -eq 0) { continue }
    W ('  <div class="group" data-kind="{0}">' -f (E $g.name))
    W '    <div class="grouphead">'
    W ('      <span class="name">{0}</span>' -f (E $g.name))
    W '      <span class="rule"></span>'
    W ('      <span class="cnt">{0}</span>' -f $items.Count)
    W '    </div>'
    W '    <ul class="items">'
    foreach ($it in $items) {
      $host_ = ''
      try { $host_ = ([uri]$it.url).Host -replace '^www\.', '' } catch { $host_ = '' }
      W '      <li class="item">'
      W ('        <div class="t">{0}</div>' -f (E $it.time))
      W '        <div class="body">'
      W ('          <h3><a href="{0}" target="_blank" rel="noopener noreferrer">{1}</a></h3>' -f (E $it.url), (E $it.title))
      W ('          <p>{0}</p>' -f (E $it.summary))
      W '          <div class="src">'
      W ('            <span>{0}</span><span class="dot">·</span>' -f (E $it.press))
      W ('            <a href="{0}" target="_blank" rel="noopener noreferrer">원문 {1}</a>' -f (E $it.url), (E $host_))
      W '          </div>'
      W '        </div>'
      W '      </li>'
    }
    W '    </ul>'
    W '  </div>'
  }
  W '</section>'
}
W '</main>'

W '<footer>'
W '  <span>연합뉴스 등 공개 기사에서 자동 수집 · 요약</span>'
W ('  <span>생성 {0}</span>' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'))
W '</footer>'
W '</div>'

W @'
<script>
(function(){
  var tabs = Array.prototype.slice.call(document.querySelectorAll('.datebar a'));
  var days = Array.prototype.slice.call(document.querySelectorAll('.day'));
  if (!tabs.length || !days.length) return;
  function mark(id){
    tabs.forEach(function(a){
      var on = a.getAttribute('data-d') === id;
      a.classList.toggle('on', on);
      if (on && a.parentNode.parentNode.scrollWidth > a.parentNode.parentNode.clientWidth) {
        a.scrollIntoView({block:'nearest', inline:'nearest'});
      }
    });
  }
  if ('IntersectionObserver' in window){
    var io = new IntersectionObserver(function(entries){
      var vis = entries.filter(function(e){ return e.isIntersecting; })
                       .sort(function(a,b){ return a.boundingClientRect.top - b.boundingClientRect.top; });
      if (vis.length) mark(vis[0].target.id.slice(1));
    }, {rootMargin:'-56px 0px -70% 0px', threshold:0});
    days.forEach(function(d){ io.observe(d); });
  }
  tabs.forEach(function(a){
    a.addEventListener('click', function(){ mark(a.getAttribute('data-d')); });
  });
})();
</script>
'@

$html = $sb.ToString()
if ($Full) {
  # <title>/<link>/<style> 를 head 로 올린 완전한 문서로 감싼다
  $headEnd = $html.IndexOf('</style>')
  $head = ''; $body = $html
  if ($headEnd -gt 0) {
    $head = $html.Substring(0, $headEnd + 8)
    $body = $html.Substring($headEnd + 8)
  }
  $desc = '속보·사건사고·해외·경제 주요 기사를 날짜별로 요약하고 원문 링크를 모았습니다. 매일 자동 갱신.'
  $html = @"
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="$desc">
<meta name="color-scheme" content="light dark">
<meta property="og:title" content="놓치면 안 되는 속보">
<meta property="og:description" content="$desc">
<meta property="og:type" content="website">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📰</text></svg>">
$head
</head>
<body>
$body
</body>
</html>
"@
}
$outDir = Split-Path -Parent $outPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[IO.File]::WriteAllText($outPath, $html, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("[built] {0}  ({1:N0} bytes, {2} days, {3} items)" -f $outPath, (Get-Item $outPath).Length, $days.Count, $totalItems)

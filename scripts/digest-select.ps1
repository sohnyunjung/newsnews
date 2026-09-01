<#
  digest-select.ps1
  data\news-YYYYMMDD.json  ->  digest\digests.json 에 오늘 항목 추가/교체

  LLM 없이 규칙만으로 중요 기사를 추린다.
  요약은 기사 리드문(첫 문단)을 정리해서 쓴다.

  사용:
    pwsh -File digest-select.ps1
    pwsh -File digest-select.ps1 -SinceHour 12 -KeepDays 30
#>
[CmdletBinding()]
param(
  [int]$SinceHour = 12,
  [int]$KeepDays  = 30,
  [string]$DataDir,
  [string]$DigestDir
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
if (-not $DataDir)   { $DataDir   = Join-Path $scriptRoot '..\data' }
if (-not $DigestDir) { $DigestDir = Join-Path $scriptRoot '..\digest' }

$now      = Get-Date
$today    = $now.ToString('yyyy-MM-dd')
$yday     = $now.AddDays(-1)
$newsFile = Join-Path $DataDir ("news-{0}.json" -f $now.ToString('yyyyMMdd'))
if (-not (Test-Path $newsFile)) { throw "not found: $newsFile  (collect-news.ps1 을 먼저 실행하세요)" }

$src = Get-Content $newsFile -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ("[input] {0} articles  ({1} ~ {2})" -f $src.total, $src.window_start, $src.window_end)

# ---------------------------------------------------------------- 노이즈 제거
$noise = '주의보|경보 해제|폭염|호우주의|풍랑|기상청 데이터|프로야구|프로축구|K리그|배구|농구|골프|MLB|야구|축구|아시안게임|올림픽|' +
         '\[인사\]|\[부고\]|부고\]|\[신간\]|\[표\]|\[게시판\]|\[동정\]|소식\]|\[일문일답\]|헤드라인\]|\[포토\]|\[르포\]|\[기고\]|\[칼럼\]|' +
         '날씨|미세먼지|운세|박스오피스|\[특징주\]|\[AI픽\]|\[바이오스냅\]|\[테크스냅\]|\[영상\]|\[쇼츠\]|\[사진\]|\[머니톡스\]|\[글로컬\]|' +
         '축제|공모전|박람회|전시회|기념식|위촉|임명장|간담회 개최|협약 체결|업무협약|MOU|기부|장학금|성금|' +
         '채용 공고|모집 공고|할인 행사|출시 기념|이벤트|응모|수상작|선정 발표|' +
         # 문화·연예·생활 (브리핑 대상 아님)
         '음악회|콘서트|공연|앨범|싱글|뮤지컬|영화제|드라마|예능|배우|가수|아이돌|팬미팅|비엔날레|' +
         '전시|관람객|맛집|여행|관광객 유치|먹거리|레시피|반려동물|건강식품|' +
         # 지자체 미시 행정
         '지역화폐|상품권|재난지원금 지급|주민자치|반상회|마을사업|정비사업 시공사|둘레길|야시장'

# ---------------------------------------------------------------- 분류 규칙
$kwIncident = '화재|불이 나|사망|숨진|숨져|추락|붕괴|매몰|침몰|실종|참사|사고|충돌|전복|폭발|누출|' +
              '구속|검거|송치|체포|영장|기소|압수수색|적발|입건|혐의|수사|재판|선고|판결|징역|벌금|' +
              '살해|폭행|성범죄|음주운전|사기|횡령|뺑소니|학대|과징금|제재|리콜|감염|확진'
$kwEconomy  = '환율|코스피|코스닥|증시|주가|금리|국고채|채권|물가|소비자물가|수출|수입|무역|경상수지|' +
              '예산|세수|세금|재정|부동산|아파트|분양|전세|주택|대출|은행|보험|펀드|연금|' +
              '반도체|배터리|자동차|조선|철강|유가|원유|실적|영업이익|매출|투자|고용|실업|임금|최저임금|' +
              'GDP|성장률|한국은행|기획재정부|금융위|공정위|국제유가'
$kwWorld    = '미국|중국|일본|러시아|우크라이나|이란|이스라엘|유럽|EU|영국|프랑스|독일|인도|대만|베트남|' +
              '트럼프|시진핑|푸틴|네팔|현지시간|외신|로이터|AFP|CNN|백악관|유엔|나토|NATO|' +
              '뉴욕증시|월가|연준|Fed|해외|국제|정상회의|수교|제재'
$kwBreaking = '대통령|청와대|국무총리|장관|국회|여당|야당|민주당|국민의힘|대법원|헌법재판소|검찰|공수처|특검|' +
              '사퇴|사의|경질|지명|임명|해임|탄핵|개각|국정감사|본회의|의결|공포|발표|지지율|여론조사|' +
              '정부, |당정|국무회의|예산안|법안|개정안'

# 점수 가중치 — 최신순보다 중요도가 앞서도록 배점한다
$kwTop  = '대통령|국무총리|사퇴|사의|경질|개각|탄핵|계엄|특검|구속|영장 발부|' +
          '사망|숨진|숨져|참사|폭발|붕괴|침몰|추락|매몰|화재|실종|사망자|' +
          '기준금리|환율|코스피|물가|국제유가|국채금리|예산안|예산 편성|지출구조조정|추경|국방비|' +
          '전쟁|공습|미사일|보복|피격|테러|핵실험|' +
          '역대 최대|역대 최저|사상 최대|사상 첫|사상 최고|30년 만|첫 돌파'
$kwMid  = '장관|청와대|국회|여당|야당|대법원|헌법재판소|검찰|공수처|경찰청|금융위|한국은행|기획재정부|' +
          '지명|임명|해임|의결|공포|발표|지지율|여론조사|법안|개정안|수출|수입|무역수지|고용|실업|' +
          '반도체|배터리|주택공급|분양|전세|대출 규제|과징금|제재|기소|송치|검거'
$kwLow  = '군수|구청장|시의회|군의회|읍면동|주민센터|동아리|체험|캠페인|홍보|시범 운영|' +
          '개장|개관|착공|준공|선포식|발대식|출범식|워크숍|세미나|포럼|토론회|' +
          '표창|수상|봉사활동|위문|헌혈|다짐대회|안전점검|점검 나서|간담회|설명회|' +
          '지원 협약|상생|나눔|사회공헌|캠페인|우수 사례|시상|공모|모집'

function Clean-Summary {
  param([string]$s)
  if (-not $s) { return '' }
  $t = $s
  # 부제(리드 앞 요약줄) 제거 후 본문 시작점 찾기: "(서울=연합뉴스) 홍길동 기자 = " 형태
  $m = [regex]::Match($t, '\([^)]{0,30}=\s*연합뉴스[^)]{0,20}\)\s*(?:[^=]{0,60}?기자\s*)?=\s*')
  if ($m.Success) { $t = $t.Substring($m.Index + $m.Length) }
  $t = $t -replace '&apos;', "'" -replace '&#x27;', "'" -replace '&quot;', '"' -replace '&nbsp;', ' '
  $t = $t -replace '[a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', ''      # 기자 이메일
  $t = $t -replace '※[^.]*\.', ''                                            # 자동작성 고지
  $t = ($t -replace '\s+', ' ').Trim()
  # 2~3문장까지만
  $parts = [regex]::Split($t, '(?<=다\.)\s+')
  $out = ''
  foreach ($p in $parts) {
    if ($out.Length -ge 150) { break }
    if ($out) { $out += ' ' }
    $out += $p.Trim()
    if ($out.Length -ge 220) { break }
  }
  if (-not $out) { $out = $t }
  if ($out.Length -gt 300) {
    $cut = $out.Substring(0, 300)
    $lastStop = $cut.LastIndexOf('다.')
    if ($lastStop -gt 120) { $out = $cut.Substring(0, $lastStop + 2) } else { $out = $cut.TrimEnd() + '…' }
  }
  return $out.Trim()
}

# 해외 판별 보조: 리드문에 '(현지시간)'이 있으면 사실상 해외발 기사다
$kwForeignStrong = '미군|미국|중국|일본|러시아|우크라이나|이란|이스라엘|유럽|영국|프랑스|독일|인도|대만|베트남|네팔|' +
                   '우즈베크|카자흐|키르기스|몽골|태국|필리핀|인도네시아|말레이시아|싱가포르|호주|캐나다|멕시코|브라질|' +
                   '사우디|아랍에미리트|UAE|튀르키예|이집트|나이지리아|콩고|케냐|스위스|스페인|이탈리아|노르웨이|스웨덴|폴란드|' +
                   '트럼프|시진핑|푸틴|헤그세스|백악관|크렘린|유엔|나토|NATO|연준|월가|뉴욕증시|현지시간|외신'

function Clean-Title {
  param([string]$s)
  if (-not $s) { return '' }
  $t = $s -replace '&apos;', "'" -replace '&#x27;', "'" -replace '&quot;', '"' -replace '&nbsp;', ' '
  # 한자 약칭을 읽기 쉽게
  $map = @{ '靑'='청와대'; '李'='이재명'; '尹'='윤석열'; '與'='여당'; '野'='야당'; '韓'='한국'; '美'='미국';
            '中'='중국'; '日'='일본'; '北'='북한'; '軍'='군'; '檢'='검찰'; '曺'='조희대' }
  foreach ($k in $map.Keys) { $t = $t.Replace($k, $map[$k]) }
  return ($t -replace '\s+', ' ').Trim()
}

function Get-Category {
  param($item)
  $t = $item.title
  $s = $item.summary

  # 한국 정부·기관이 주어면 해외 기사가 아니다
  $koreanActor = '^(청와대|정부|외교부|산업장관|국토부|기재부|한국은행|금융위|국방부|통일부|여당|야당|국회|대통령|총리|[가-힣]{2,4}\s?장관)'

  if ($item.section -eq '국제') { return '해외' }
  if (($s -match '현지시간' -or $t -match $kwForeignStrong) -and $t -notmatch $koreanActor) {
    if ($t -notmatch '한국은행|기획재정부|국내 증시|코스피|코스닥') { return '해외' }
  }
  # 사건·사고는 실제 사건이어야 한다 (정치 발언·의결은 제외)
  if ($t -match $kwIncident -and
      $t -notmatch '의결|발언|주장|촉구|비판|논평|성명|반발|공방|질의|선언|지명철회|밀어붙|낭패|요구|제안|입장|해명|엄호|정조준') {
    return '사건·사고 (국내)'
  }
  if ($t -match $kwEconomy -or $item.section -eq '경제' -or $item.section -eq '산업') { return '경제' }
  # 속보는 정부·국회·사법부의 실제 결정/조치만
  if ($item.section -match '정치|주요|최신|사회' -and $t -match $kwBreaking) { return '속보' }
  return $null
}

function Get-Score {
  param($item, [datetime]$pub)
  $s = 0.0
  $t = $item.title

  # 중요도가 지배적이어야 한다
  if ($t -match $kwTop) { $s += 7 }
  if ($t -match $kwMid) { $s += 3 }
  if ($t -match $kwLow) { $s -= 6 }

  if ($t -match '\(종합\d*보?\)') { $s += 2.5 }   # 가장 완성된 판
  if ($t -match '^\[속보\]')      { $s += 2 }
  if ($t -match '^\[\d{4}예산\]') { $s += 3 }     # 예산안 시리즈는 중요
  if ($item.section -eq '지역')   { $s -= 5 }
  if ($t -match '^\[[^\]]+\]\s*$|^\[.*소식\]') { $s -= 5 }

  # 지자체·기관 미시 기사 감점
  if ($t -match '^[가-힣]{2,4}(시|군|구|도)(의회)?[,\s]') { $s -= 4 }

  if ($item.summary) { $s += [Math]::Min(1.5, $item.summary.Length / 400.0) }

  # 최신 가점은 보조적으로만 (0~1.5)
  $ageH = ($now - $pub).TotalHours
  $s += [Math]::Max(0, 1.5 - ($ageH / 18))
  return $s
}

# ---------------------------------------------------------------- 후보 구성
$cands = New-Object System.Collections.ArrayList
foreach ($a in $src.articles) {
  if ($a.title -match $noise) { continue }
  if ($a.title.Length -lt 10) { continue }
  $pub = $null
  try { $pub = [datetime]::Parse($a.published) } catch { continue }
  $cat = Get-Category $a
  if (-not $cat) { continue }
  $sum   = Clean-Summary $a.summary
  $score = Get-Score $a $pub

  # 리드문이 짧아도 중요한 기사는 살린다 (큰 기사일수록 리드가 한 줄인 경우가 많다)
  if ($sum.Length -lt 25) { continue }
  if ($sum.Length -lt 45 -and $score -lt 8.0) { continue }
  if ($score -lt 2.0) { continue }

  $label = $pub.ToString('HH:mm')
  if ($pub.Date -ne $now.Date) { $label = ('{0}일 {1}' -f $pub.Day, $pub.ToString('HH:mm')) }

  [void]$cands.Add([pscustomobject]@{
    time = $label; title = (Clean-Title $a.title); summary = $sum; press = '연합뉴스'; url = $a.url
    _cat = $cat; _score = $score; _pub = $pub
    _key = ([regex]::Replace($a.title, '[^0-9A-Za-z가-힣]', '')).ToLower()
  })
}
Write-Host ("[cands] {0} after filtering" -f $cands.Count)

# ---------------------------------------------------------------- 유사 제목 중복 제거
function Get-Bigrams {
  param([string]$s)
  $set = @{}
  for ($i = 0; $i -lt $s.Length - 1; $i++) { $set[$s.Substring($i, 2)] = $true }
  return $set
}
function Get-Similarity {
  param($A, $B)          # 자카드 유사도 (문자 2-gram)
  if ($A.Count -eq 0 -or $B.Count -eq 0) { return 0 }
  $inter = 0
  foreach ($k in $A.Keys) { if ($B.ContainsKey($k)) { $inter++ } }
  return $inter / [double]($A.Count + $B.Count - $inter)
}

foreach ($c in $cands) { $c | Add-Member -NotePropertyName _bg -NotePropertyValue (Get-Bigrams $c._key) -Force }

$sorted = @($cands | Sort-Object -Property _score -Descending)
$picked = New-Object System.Collections.ArrayList
foreach ($c in $sorted) {
  $dup = $false
  foreach ($p in $picked) {
    if ((Get-Similarity $p._bg $c._bg) -ge 0.42) { $dup = $true; break }   # 같은 사안의 다른 판
  }
  if (-not $dup) { [void]$picked.Add($c) }
}

# ---------------------------------------------------------------- 분류별 선별 (전날 기사 최소 보장)
$quota = @{ '속보' = 8; '사건·사고 (국내)' = 6; '해외' = 8; '경제' = 8 }
$minPrev = @{ '속보' = 2; '사건·사고 (국내)' = 1; '해외' = 2; '경제' = 1 }
$order = @('속보', '사건·사고 (국내)', '해외', '경제')

$groups = New-Object System.Collections.ArrayList
foreach ($cat in $order) {
  $pool  = @($picked | Where-Object { $_._cat -eq $cat })
  $prev  = @($pool | Where-Object { $_._pub.Date -ne $now.Date })
  $curr  = @($pool | Where-Object { $_._pub.Date -eq $now.Date })

  $take = New-Object System.Collections.ArrayList
  foreach ($x in ($prev | Select-Object -First $minPrev[$cat])) { [void]$take.Add($x) }
  foreach ($x in $curr) {
    if ($take.Count -ge $quota[$cat]) { break }
    [void]$take.Add($x)
  }
  foreach ($x in $prev) {                       # 자리가 남으면 전날 기사로 채운다
    if ($take.Count -ge $quota[$cat]) { break }
    if ($take -contains $x) { continue }
    [void]$take.Add($x)
  }
  if ($take.Count -eq 0) { continue }

  # 당일 먼저, 전날은 뒤로. 각 구간은 점수 순.
  $final = @($take | Where-Object { $_._pub.Date -eq $now.Date } | Sort-Object _score -Descending) +
           @($take | Where-Object { $_._pub.Date -ne $now.Date } | Sort-Object _score -Descending)

  [void]$groups.Add([pscustomobject]@{
    name  = $cat
    items = @($final | ForEach-Object { [pscustomobject]@{ time = $_.time; title = $_.title; summary = $_.summary; press = $_.press; url = $_.url } })
  })
  Write-Host ("  {0,-16} {1}건 (전날 {2})" -f $cat, $final.Count, @($final | Where-Object { $_.time -match '일 ' }).Count)
}

# ---------------------------------------------------------------- digests.json 갱신
$wd = @('일','월','화','수','목','금','토')[[int]$now.DayOfWeek]
$entry = [pscustomobject]@{
  date    = $today
  weekday = $wd
  window  = ('{0}월 {1}일 {2}:00 ~ {3}월 {4}일 {5}' -f $yday.Month, $yday.Day, $SinceHour.ToString('00'),
             $now.Month, $now.Day, $now.ToString('HH:mm'))
  pool    = $src.total
  groups  = $groups
}

$digestFile = Join-Path $DigestDir 'digests.json'
$days = New-Object System.Collections.ArrayList
if (Test-Path $digestFile) {
  $old = Get-Content $digestFile -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($d in $old.days) { if ($d.date -ne $today) { [void]$days.Add($d) } }
}
[void]$days.Insert(0, $entry)

$kept = @($days | Sort-Object date -Descending | Select-Object -First $KeepDays)
if (-not (Test-Path $DigestDir)) { New-Item -ItemType Directory -Path $DigestDir -Force | Out-Null }
[pscustomobject]@{ days = $kept } | ConvertTo-Json -Depth 8 |
  Out-File -FilePath $digestFile -Encoding utf8

$total = 0; foreach ($g in $groups) { $total += @($g.items).Count }
Write-Host ''
Write-Host ("[done] {0} 선별 -> {1} ({2}일치 보관)" -f $total, $digestFile, $kept.Count)

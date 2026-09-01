# 놓치면 안 되는 속보

전날 오후부터 당일 오후까지의 기사 중 **속보 · 사건사고 · 해외 · 경제**를 추려
제목 · 요약 · 원문 링크로 정리해 날짜별 페이지로 보여줍니다.

GitHub Actions가 3시간마다 자동으로 돌기 때문에 **PC 전원과 무관하게** 동작합니다.

## 실행 주기

| 시각 (한국시간) | 하는 일 |
|---|---|
| 01:10 / 04:10 / 07:10 / 10:10 / 13:10 / 16:10 / 19:10 / 22:10 | 기사 수집 + 페이지 갱신 |
| 14:05 | 그날의 기준 브리핑 |

연합뉴스는 한 번에 최근 7~8시간치만 노출하므로, 3시간마다 모아
`data/archive.json`에 누적해야 24시간 구간이 빈틈없이 채워집니다.

## 구성

```
scripts/
  collect-news.ps1    연합뉴스 목록 + 카테고리 RSS 수집 → data/archive.json 누적
  digest-select.ps1   규칙 기반으로 중요 기사 선별 → digest/digests.json
  build-page.ps1      digests.json → HTML 페이지
data/archive.json     최근 2일치 기사 원본 (수집 상태)
digest/digests.json   날짜별 브리핑 (선별·요약 결과)
docs/index.html       GitHub Pages가 서비스하는 페이지
```

## 선별 방식

LLM 없이 규칙으로 고릅니다.

- 노이즈 제외: 기상특보 자동기사, 스포츠, 인사·부고, 지자체 행사, 문화·연예 등
- 분류: 국제 섹션·해외 키워드 → 해외 / 사건 키워드 → 사건사고 / 경제 키워드 → 경제 / 정부·국회·사법부 조치 → 속보
- 점수: 중요 키워드(대통령·사퇴·화재·금리 등) 가중, 지자체 미시 기사 감점, `(종합)` 우대, 최신순은 보조
- 중복 제거: 제목 2-gram 자카드 유사도 0.42 이상이면 같은 사안으로 간주
- 요약: 기사 리드문에서 통신사 서두를 걷어내고 2~3문장으로 정리

## 수동 실행

저장소 **Actions** 탭 → `뉴스 수집 및 브리핑` → **Run workflow**

## 로컬 실행

```powershell
./scripts/collect-news.ps1
./scripts/digest-select.ps1
./scripts/build-page.ps1 -Full -OutFile docs/index.html
```

Windows PowerShell 5.1과 PowerShell Core 7 모두에서 동작합니다.

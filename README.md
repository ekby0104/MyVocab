# MyVocab 📚

> **⚠️ Disclaimer**
>
> 이 앱은 **개인 학습 목적**으로 제작된 **비공식** 단어장 학습 앱입니다.
> 네이버 및 NAVER Corp.와 어떠한 제휴 관계도 없으며, 네이버 공식 API가 아닙니다.
> 네이버 연동 기능은 본인 계정의 본인 데이터를 개인 학습 목적으로만 사용하도록 설계되었습니다.
> 이 코드를 사용하거나 수정하는 것에 대한 책임은 사용자 본인에게 있습니다.
>
> This is a **personal learning project** and is **not affiliated** with NAVER Corp.
> It is not an official Naver application. The Naver integration feature is designed
> to access the user's own data for personal learning purposes only.

---

네이버 단어장과 연동되는 iOS 단어 학습 앱. SwiftUI + SwiftData 기반으로 제작.

## ✨ 주요 기능

### 📖 단어 관리
- **전체 단어 / 즐겨찾기 / 검색** 탭 분리
- **6가지 정렬**: 최신순, 알파벳, 알파벳 역순, 즐겨찾기, 오답 순, 랜덤
- **스와이프 액션**: 오른쪽 스와이프로 즐겨찾기, 왼쪽 스와이프로 삭제
- **단어 직접 추가/편집**: 영어, 발음, 품사, 뜻, 예문, 메모 전부 편집 가능
- **단어 상세 화면**: 학습 통계, 메모, 즐겨찾기 토글

### 🔍 강력한 검색
- **한/영 통합 검색**: 영어, 한글 뜻, 발음, 예문 모두 검색 대상
- **검색 범위 선택**: 전체 / 단어 / 예문 필터
- **와일드카드 지원**:
  - `ab*` — ab로 시작 (뒤에 1글자 이상)
  - `*ing` — ing로 끝 (앞에 1글자 이상)
  - `c*t` — c와 t 사이에 1글자 이상
  - `c?t` — c+한글자+t (cat, cot, cut)
- **검색 기록**: 최근 10개 자동 저장, 탭으로 재검색
- **일괄 즐겨찾기**: 검색 결과 전체를 한 번에 즐겨찾기

### 🎮 학습 모드
- 🎴 **플래시카드**: 앞뒤 전환, 섞기, 즐겨찾기 필터
- 🎯 **퀴즈**: 4지선다, 영↔한 양방향, 문제 수 1~1000개 커스텀
- ⭐ **즐겨찾기 퀴즈**: 즐겨찾기 단어만으로 출제
- 📅 **오늘의 복습**: SRS 기반 복습 대상 단어 자동 선별
- 🔄 **틀린 단어 복습**: 자동 저장 → 복습 → 맞추면 자동 클리어

### 📅 간격 반복 학습 (SRS)
Leitner box 방식의 8단계 레벨 시스템
- Level 0 → 즉시 복습 (오답)
- Level 1 → 1일 후
- Level 2 → 3일 후
- Level 3 → 7일 후
- Level 4 → 14일 후
- Level 5 → 30일 후
- Level 6 → 60일 후
- Level 7 → 120일 후 (마스터)

정답 시 레벨 +1, 오답 시 레벨 0으로 리셋.

### 📊 학습 통계
- **요약 카드**: 전체 단어, 학습 완료, 마스터, 정답률, 즐겨찾기, 틀린 단어
- **학습 누적 바**: 정답/오답 비율 시각화
- **SRS 레벨 분포**: 레벨별 단어 수 막대 그래프
- **자주 틀리는 단어 TOP 10**: 순위와 오답 횟수 표시

### 🔊 TTS 발음
- `AVSpeechSynthesizer` 기반 영어 발음
- 단어 상세, 예문, 편집 화면에서 스피커 버튼 한 번
- 미국식 영어, 학습용 속도 (0.45x)

### 🔐 네이버 동기화
- **WebView 기반 로그인**: 네이버 공식 로그인 페이지 그대로 사용
- **쿠키 영구 저장**: 한 번 로그인 후 만료 전까지 자동 유지
- **빠른 동기화**: 탭 한 번으로 전체 단어 업데이트
- **동적 단어장 목록**: API에서 단어장 목록 자동 조회 (하드코딩 ID 없음)
- **세션 만료 자동 감지**: 만료 시 재로그인 유도

### 💾 백업 / 복원
- **전체 데이터 백업**: 단어 + 즐겨찾기 + 메모 + 학습 통계까지 JSON으로 export
- **공유 시트**: iCloud Drive, 파일 앱 등에 저장 가능
- **병합 복원**: 기존 단어는 보존하면서 백업 데이터로 즐겨찾기/메모/통계만 복원

### 📥 JSON Import
- 네이버 원본 API 응답 파싱 (`data.m_items` 구조)
- 단순 배열 포맷 지원 (전처리된 데이터용)
- HTML 태그, 엔티티 자동 정리
- 중복 감지 + 건너뛴 사유별 상세 로그

## 🛠 기술 스택

- **SwiftUI** — 전체 UI (iOS 17+)
- **SwiftData** — 단어 저장소 (`@Model`, `@Query`)
- **WKWebView** — 네이버 로그인
- **URLSession** — 쿠키 기반 API 호출
- **AVSpeechSynthesizer** — TTS
- **UserDefaults** — 쿠키, 검색 기록, 단어장 목록, 설정 저장

## 📁 프로젝트 구조

```
MyVocab/
├── App/
│   └── MyVocabApp.swift            // 진입점 + URL 스킴 + 자동 DB 복구
├── Models/
│   └── Word.swift                  // SwiftData 모델 (SRS 필드 포함)
├── Services/
│   ├── NaverImporter.swift         // 네이버 JSON 파서
│   ├── NaverSync.swift             // 네이버 API + 쿠키/단어장 저장
│   ├── SpeechService.swift         // TTS 래퍼
│   ├── SRSService.swift            // Leitner box SRS 알고리즘
│   └── BackupService.swift         // 백업/복원 로직
└── Views/
    ├── RootTabView.swift           // 5탭 네비게이션
    ├── WordListView.swift          // 전체/즐겨찾기 (스와이프 액션, 정렬)
    ├── WordDetailView.swift        // 상세 + TTS + 편집 진입
    ├── WordEditView.swift          // 단어 추가/편집 폼
    ├── SearchView.swift            // 와일드카드 검색 + 검색 기록
    ├── GameView.swift              // 학습 모드 선택 + 오늘의 복습
    ├── FlashcardView.swift         // 플래시카드
    ├── QuizView.swift              // 4지선다 퀴즈 + SRS 적용
    ├── StatsView.swift             // 통계 대시보드
    ├── NaverSyncView.swift         // 네이버 WebView 로그인
    ├── SettingsView.swift          // 설정 (섹션 분리)
    └── ShareSheet.swift            // UIActivityViewController 래퍼
```

## 🚀 시작하기

### 요구사항
- macOS 14+
- Xcode 15+
- iOS 17+ 실기기 또는 시뮬레이터

### 빌드
1. 이 저장소를 clone
2. `MyVocab.xcodeproj` 열기
3. Signing & Capabilities에서 본인 Apple ID 선택
4. ⌘R로 실행

### 첫 사용 흐름
1. **설정 → 네이버 로그인** → WebView에서 네이버 로그인
2. **단어장 목록 새로고침** → 본인의 단어장 목록 자동 로드
3. **단어장 선택** → 드롭다운에서 원하는 단어장
4. **빠른 동기화** → 단어 가져오기
5. **게임 탭 → 퀴즈 / 플래시카드** → 학습 시작!

## ⚠️ 주의사항

- 네이버 공식 API가 아니므로 네이버 측 변경에 따라 작동이 중단될 수 있습니다
- 무료 Apple 개발자 계정 사용 시 7일마다 재설치 필요
- SwiftData 모델 변경 시 자동으로 DB 초기화됨 (앱은 계속 동작)
- **데이터 보존이 중요하면 정기적으로 백업 파일 만들기 권장**

## 🗺 로드맵

### ✅ 완료
- Phase 1: TTS + 단어 추가/편집
- Phase 2-A: SRS + 통계 + 백업/복원
- Phase 2-B: 오늘의 복습 + 검색 기록

### 💭 아이디어
- 🔔 학습 알림 (매일 정해진 시간)
- ⌨️ 타자 입력 퀴즈 (스펠링 학습)
- 🔀 단어 매칭 게임
- 🏷 태그/카테고리 시스템
- 🔥 연속 학습일 (스트릭)
- 📈 주간/월간 리포트
- 🌙 다크모드 강제 토글
- 📱 홈 화면 위젯 (유료 개발자 계정 필요)

## License

MIT License — 개인 학습용 프로젝트

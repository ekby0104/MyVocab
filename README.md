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

네이버 단어장과 연동되는 iOS 단어 학습 앱.

## 기능

- 📖 **전체/즐겨찾기/검색** — 한글·영어 통합 검색, 일괄 즐겨찾기
- 🎴 **플래시카드** — 앞뒤 전환, 섞기, 즐겨찾기 필터
- 🎯 **퀴즈** — 4지선다, 영↔한 양방향, 문제 수 1~1000개 커스텀
- 🔄 **틀린 단어 복습** — 자동 저장 → 복습 → 맞추면 클리어
- 🔐 **네이버 동기화** — WebView 로그인 + 쿠키 저장 + 빠른 동기화
- 📚 **단어장 선택** — 동적으로 네이버에서 단어장 목록 가져오기
- 📥 **JSON import** — 파일/공유시트 양방향 지원

## 기술 스택

- SwiftUI + SwiftData (iOS 17+)
- WKWebView (네이버 로그인)
- URLSession (쿠키 기반 API 호출)

## 프로젝트 구조

```
MyVocab/
├── App/
│   └── MyVocabApp.swift          // 진입점 + URL 스킴 + 파일 import
├── Models/
│   └── Word.swift                // SwiftData 모델
├── Services/
│   ├── NaverImporter.swift       // JSON 파서
│   └── NaverSync.swift           // 네이버 API + 쿠키 저장
└── Views/
    ├── RootTabView.swift
    ├── WordListView.swift        // 전체/즐겨찾기 (스와이프 액션)
    ├── WordDetailView.swift
    ├── SearchView.swift          // 일괄 즐겨찾기
    ├── GameView.swift            // 학습 모드 선택 + 틀린 단어 복습
    ├── FlashcardView.swift
    ├── QuizView.swift
    ├── NaverSyncView.swift       // WebView 로그인
    └── SettingsView.swift
```

## 주의사항

- 네이버 공식 API가 아니므로 네이버 측 변경에 따라 작동이 중단될 수 있습니다
- 무료 Apple 개발자 계정 사용 시 7일마다 재설치 필요
- SwiftData는 모델 변경 시 기존 DB 자동 초기화

## License

MIT (개인 학습용)

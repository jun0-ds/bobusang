> 이 절은 bobusang setup.sh가 marker block(`bobusang:sync:start/end`)으로 관리한다 — marker 밖(절 헤더·owner 주석)은 보존되고, marker 안은 setup.sh 실행 때 이 template으로 덮어쓰여진다. 절차 세부는 leaf 문서 `docs/sync-guide.md`에 두고, 여기엔 매 세션 필요한 always-on 규칙만 남긴다. **본 template은 maintainer instance(jun0-ds, 두 리포 구조) 예시 — fork 시 자기 sync topology로 교체.**

- **브랜치**: 모든 기기가 `main`에서 직접 작업한다 (device 브랜치 없음).
- **싱크 요청 trigger**: "싱크해줘 / 푸시해줘 / 메모리 올려줘 / sync" 를 보면 → `~/control-tower/munteok-anchae/docs/sync-guide.md`를 Read하고 그 절차대로 진행한다 (두 리포 구조·자동/수동 싱크 단계·커밋 컨벤션이 거기 풀려 있다).
- **커밋 attribution**: 모든 commit은 사용자가 author, 메시지 마지막 줄에 `Co-Authored-By: Claude <noreply@anthropic.com>` trailer를 단다 (모델명은 쓰는 모델에 맞게). 근거·확인 명령·잘못 박힌 author 정정법은 sync-guide.md.
- **구조변경 신호**: settings.json·CLAUDE.md·hooks/ 변경은 `sync: [구조변경] …` 로 커밋한다 → 다른 기기는 새 세션 권장 (detect-changes.sh가 감지·경고).

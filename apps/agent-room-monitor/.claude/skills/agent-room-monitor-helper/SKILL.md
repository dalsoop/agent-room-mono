---
name: agent-room-monitor-helper
description: agent-room-monitor 앱에서 작업할 때 사용. 트리거 — "agent-room-monitor 도움", "agent-room-monitor 작업". 앱이 게시한 상태 파일을 작업 컨텍스트로 읽는다.
---

# agent-room-monitor helper

agent-room-monitor 전용 스킬. 앱의 상태(열린 대상, 최근 작업 등)를 컨텍스트로 읽어 도움을 제공한다.

## 워크플로우

1. 앱 상태 파일에서 현재 세션 컨텍스트 확인.
2. 작업에 맞는 제안/실행.
3. 안전 제약(읽기 전용 모드 등) 존중.

## CLI

```
agent-room-monitor agent scan      # 실행 중 에이전트 + 이 앱 카드
agent-room-monitor skill list      # 워크스페이스/전역 스킬
agent-room-monitor chat --backend claude "..."
```

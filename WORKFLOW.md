---
board:
  title: "ML Root Problems"
  description: "Exploring fundamental problems in machine learning"
  dispatch_priority_mode: hybrid
  priority_weight: 0.7
  upvote_weight: 0.3

polling:
  interval_ms: 10000

workspace:
  root: ".chorus/workspaces"

agent:
  command: "claude"
  max_concurrent: 2
  max_retries: 3
  stall_timeout_ms: 300000
---

# Task: {{idea.identifier}} — {{idea.title}}

You are working on an idea from the **{{board.title}}** board.

## Idea Details

- **Identifier**: {{idea.identifier}}
- **Title**: {{idea.title}}
- **Description**: {{idea.description}}
- **Tags**: {{idea.tags}}
- **Priority**: {{idea.priority}}

## Instructions

1. Read the idea description carefully.
2. Create a plan for implementation.
3. Implement the solution in the workspace.
4. Write tests for your implementation.
5. Summarize what you built and any follow-up work needed.

This is attempt: {{attempt}}.

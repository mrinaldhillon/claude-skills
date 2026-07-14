---
description: Print the exact terminal command to run the milestone loop (resolves the scaffold plugin path).
argument-hint: milestones/<name>.json
allowed-tools: Bash(printf:*)
---
The milestone runner (ADR 0004/0006) manages context by spawning fresh `claude -p`
sessions, so it runs from a plain terminal — NOT nested inside this session. Resolve
and print the command for the config in `$ARGUMENTS`:

    printf 'Run this in a terminal at your repo root:\n\n  bash "%s/scripts/milestone-runner.sh" %s\n' "${CLAUDE_PLUGIN_ROOT}" "$ARGUMENTS"

Do not execute the runner from within this session.

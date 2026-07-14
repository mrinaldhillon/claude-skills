# deep-research-tiered — run fan-out research with per-stage model pins and budget safety

> Human-facing pointer. **`SKILL.md` is the authoritative source** for this skill's rules and procedure; this README summarizes and links, and may lag — when they differ, SKILL.md wins.

**What it gives you.** The corrected way to run fan-out web-search research in this repo. It encodes the fix for a ~1.95M-token burn: per-stage model pins (Haiku for scope/search/fetch, Sonnet for verify, Opus for synthesis), a budget guard, per-phase checkpoints to durable memory, and a synthesis step that always runs even when partial. Use it for high-value, breadth-first research tasks where unpredictable decomposition earns the multi-agent token premium.

**When it fires.** Trigger whenever you would reach for the bundled `deep-research` harness, or any time you fan out web search → fetch → verify → synthesize across many subagents.

**Key ideas (summarized — see `SKILL.md` for the authoritative wording):**
- Pin `opts.model` on every stage — Haiku for scope/search/fetch, Sonnet for claim verification (research-claim grading only, not the code-correctness gate), Opus for synthesis; an unset stage silently inherits the session's strong default, which is the root cause of the token burn.
- Guard the `budget` object before fan-out; cap fleet size before the session limit; log any dropped claims so truncation is visible, not silent.
- Checkpoint the distilled payload (verified claims, sources, confidence tags) to a durable memory file as an explicit step after Verify, before Synthesize — `SubagentStop` does not fire for Workflow-internal agents, so this must be a script step, not a hook.
- Synthesis always runs: read from the checkpoint and write a partial, labeled report if verification is incomplete — a partial cited report beats a dead run with findings stranded in memory.
- Single writer for the final report: parallelize investigation (search, fetch, verify) freely; serialize the write — parallel section writers make conflicting implicit choices that degrade coherence.

See [`SKILL.md`](SKILL.md) for the full procedure.

# meowhub

Private, self-hosted operations platform for a household — the successor in
spirit to [nexus](https://github.com/retran/nexus), rebuilt on low-code
building blocks instead of a bespoke service.

The first slice is an expense-tracking Telegram bot: send an expense as text,
a receipt photo or a voice note, and an AI agent records it, answers questions
about the ledger and produces reports.

Status: early. No running system yet — twenty-six architecture decisions are
agreed, and the first specs are in progress.

Licensed under the [Apache License 2.0](LICENSE); see [NOTICE](NOTICE) for the
licences of the components this system runs.

## Layout

```
specs/           what we are building and why
docs/product/    vision, glossary
docs/architecture/  architecture overview and ADRs
docs/standards/  how we work, how a screen gets designed, what the system asks of people
```

The step-by-step build order, with the documentation that goes with each phase,
is in [docs/implementation-plan.md](docs/implementation-plan.md).

Development is spec-driven: spec → plan → tasks → code. The process lives in
[CLAUDE.md](CLAUDE.md) and in full in
[docs/standards/spec-driven-workflow.md](docs/standards/spec-driven-workflow.md).

A new feature starts with `/spec-new <description>` in Claude Code.

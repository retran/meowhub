# meowhub

A private, self-hosted operations platform for one household. It succeeds
[nexus](https://github.com/retran/nexus) in spirit, and we rebuilt it on
low-code building blocks in place of a bespoke service.

The first slice is an expense-tracking Telegram bot: you send an expense as
text, a receipt photo or a voice note, and an AI agent records it, answers
questions about the ledger, and produces reports.

Status: early. Nothing runs as a deployed system yet, though the whole stack
runs and is tested on a laptop. Forty-six architecture decisions are agreed,
four slices are built (infrastructure, identity, expense capture, and queries
with the digests), and the remaining seven are specified.

The project is licensed under the [Apache License 2.0](LICENSE), and
[NOTICE](NOTICE) lists the licences of the components this system runs.

## Quick start

You need Docker and [Task](https://taskfile.dev) (`brew install go-task`), and
nothing else installed natively. Copy the environment file, fill in the
PostgreSQL variables, then bring the stack up and run the tests:

```
cp .env.example .env
# fill in POSTGRES_*, DATABASE_URL at minimum
task up
task test
```

`task up` starts PostgreSQL and applies the migrations in containers, and
`task test` runs the suite against a throwaway database.
[docs/guides/local-development.md](docs/guides/local-development.md) explains
what else comes up and how to work with it.

## Layout

The repository keeps what we are building apart from how we work:

```
specs/           what we are building and why
docs/product/    vision, glossary
docs/architecture/  architecture overview and ADRs
docs/standards/  how we work, how a screen gets designed, what the system asks of people
```

[docs/implementation-plan.md](docs/implementation-plan.md) gives the
step-by-step build order, with the documentation that goes with each phase.

We develop spec-driven, in four steps: a spec, then a plan, then tasks, then
code. [CLAUDE.md](CLAUDE.md) summarises the process, and
[docs/standards/spec-driven-workflow.md](docs/standards/spec-driven-workflow.md)
describes it in full.

Start a new feature with `/spec-new <description>` in Claude Code.

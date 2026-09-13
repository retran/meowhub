# Tools

The agent's declared tool contract (ADR 0039): stable names, JSON input
schemas, the permission each requires, and whether each is read-only or
mutating. Mounted read-only into the n8n container alongside `prompts/`,
with the same fail-loudly-if-absent rule.

Empty for now: the first real tools arrive with spec 0003. This file exists
so the mount is never empty.

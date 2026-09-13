# Prompts

Versioned, bilingual prompt files (ADR 0025). One task, one prompt — capture
extraction, receipt reading, statement reading and report answering are
separate, each with its own declared output schema. Mounted read-only into
the n8n container; a missing or empty mount fails startup loudly rather than
failing silently at the first capture.

Empty for now: the first real prompt arrives with spec 0003 (text expense
capture). This file exists so the mount itself is never empty, which is what
the startup check in `n8n/docker/docker-entrypoint-wrapper.sh` verifies.

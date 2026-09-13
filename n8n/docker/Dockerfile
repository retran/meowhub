# n8n with a startup check that the prompt and tool mounts are actually
# present (ADR 0025, ADR 0039, spec 0001 T9). Pinned to an exact version
# (checked 2026-09-12); bump deliberately, never float on :latest.
FROM n8nio/n8n:2.38.7

USER root
COPY docker-entrypoint-wrapper.sh /docker-entrypoint-wrapper.sh
RUN chmod +x /docker-entrypoint-wrapper.sh
USER node

ENTRYPOINT ["/docker-entrypoint-wrapper.sh"]
CMD ["n8n"]

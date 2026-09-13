# The one container allowed to run scheduled jobs (spec 0001 T16, R13):
# nothing runs on the host (a standing rule for this deployment), so "on a
# schedule" has to mean a container with cron in it. Talks to the same
# Docker daemon as everything else via the socket, so `docker compose exec`
# inside this container reaches the real running services exactly as it
# does from a developer's own shell.
FROM docker:27-cli

RUN apk add --no-cache bash python3 curl docker-cli-compose dcron tini

COPY crontab /etc/crontabs/root

WORKDIR /workspace
# crond calls setpgid per job it dispatches, which fails under some
# container runtimes when crond itself is PID 1 — tini as a proper init
# gives it somewhere else to be.
ENTRYPOINT ["tini", "--", "crond", "-f", "-l", "2"]

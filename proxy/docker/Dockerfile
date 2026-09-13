# Stock Caddy has no rate limiting; the caddy-ratelimit plugin has to be
# compiled in (spec 0001 T12, R5a). Built here rather than pulled pre-built
# so the version is pinned and reproducible from source, same pattern as
# db/docker.
FROM caddy:2-builder-alpine AS build
RUN xcaddy build --with github.com/mholt/caddy-ratelimit@v0.1.0

FROM caddy:2-alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy

# The token bridge (ADR 0041, spec 0002 T7) — one file, standard library
# plus a single Postgres driver, deliberately: this is a small, tested,
# stateless piece, not a framework.
FROM python:3.12-alpine
RUN apk add --no-cache postgresql-libs && \
    apk add --no-cache --virtual .build-deps postgresql-dev gcc musl-dev && \
    pip install --no-cache-dir psycopg2-binary==2.9.10 && \
    apk del .build-deps
COPY server.py /server.py
EXPOSE 8095
CMD ["python3", "/server.py"]

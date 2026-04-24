# bi/Dockerfile
# Extends the official Superset image with drivers needed for this platform.
FROM apache/superset:5.0.0

USER root

# Superset runs inside /app/.venv which has no pip binary.
# Install directly into the venv's site-packages using the system pip.
RUN pip install --no-cache-dir \
    --target /app/.venv/lib/python3.10/site-packages \
    psycopg2-binary \
    sqlalchemy-trino \
    trino[sqlalchemy]

USER superset

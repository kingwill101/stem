FROM postgres:14

COPY docker/testing/postgres/certs/root.crt /etc/postgres/certs/root.crt
COPY docker/testing/postgres/certs/server.crt /etc/postgres/certs/server.crt
COPY docker/testing/postgres/certs/server.key /etc/postgres/certs/server.key

RUN chown postgres:postgres /etc/postgres/certs/* \
    && chmod 600 /etc/postgres/certs/server.key

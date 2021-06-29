FROM postgres:13-alpine AS build

ENV PLPGSQL_CHECK_VERSION 1.17.1
ENV PLPGSQL_CHECK_SHA256 a0441308ad47fdfdc88e7f8e36ce2bf3bcd5215bf4c23767787128e27c0a3990

RUN set -e \
    && apk add --no-cache --virtual .fetch-deps \
        ca-certificates \
        openssl \
        tar \
    && wget -O plpgsql_check.tar.gz "https://github.com/okbob/plpgsql_check/archive/v$PLPGSQL_CHECK_VERSION.tar.gz" \
    && echo "$PLPGSQL_CHECK_SHA256 *plpgsql_check.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/src/plpgsql_check \
    && tar --extract \
        --file plpgsql_check.tar.gz \
        --directory /usr/src/plpgsql_check \
        --strip-components 1 \
    && rm plpgsql_check.tar.gz \
    \
    && apk add --no-cache --virtual .build-deps \
        make \
        gcc \
        libc-dev \
        postgresql-dev \
    && cd /usr/src/plpgsql_check \
    && make -j$(nproc) \
    && make install prefix=/usr/local \
    \
    && cd / \
    && rm -rf /usr/src/postgis \
    && apk del .fetch-deps .build-deps

COPY postgres/ /docker-entrypoint-initdb.d/

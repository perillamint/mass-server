# syntax=docker/dockerfile:1
ARG TARGETPLATFORM
ARG PYTHON_VERSION="3.11"

#####################################################################
#                                                                   #
# Build Wheels                                                      #
#                                                                   #
#####################################################################
FROM python:${PYTHON_VERSION}-slim as wheels-builder
ARG TARGETPLATFORM

# Install buildtime packages
RUN set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libffi-dev \
        cargo \
        git \
        curl

WORKDIR /wheels
COPY requirements_all.txt .


# build python wheels for all dependencies
RUN set -x \
    && pip install --upgrade pip \
    && pip install build maturin \
    && pip wheel -r requirements_all.txt


#####################################################################
#                                                                   #
# Final Image                                                       #
#                                                                   #
#####################################################################
FROM python:${PYTHON_VERSION}-slim AS final-build
WORKDIR /app

# Required to persist build arg
ARG MASS_VERSION
ARG TARGETPLATFORM

RUN set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        wget \
        tzdata \
        ffmpeg \
        libsox-fmt-all \
        libsox3 \
        sox \
        cifs-utils \
        libnfs-utils \
        libjemalloc2 \
    # cleanup
    && rm -rf /tmp/* \
    && rm -rf /var/lib/apt/lists/*


# https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/syntax.md#build-mounts-run---mount
# Install all built wheels
RUN --mount=type=bind,target=/tmp/wheels,source=/wheels,from=wheels-builder,rw \
    set -x \
    && pip install --upgrade pip \
    && pip install --no-cache-dir /tmp/wheels/*.whl

# Install Music Assistant from published wheel
RUN pip3 install \
        --no-cache-dir \
        music-assistant[server]==${MASS_VERSION} \
    && python3 -m compileall music_assistant

# Enable jemalloc
RUN \
    export LD_PRELOAD="$(find /usr/lib/ -name *libjemalloc.so.2)" \
    export MALLOC_CONF="background_thread:true,metadata_thp:auto,dirty_decay_ms:20000,muzzy_decay_ms:20000"

# Set some labels
LABEL \
    org.opencontainers.image.title="Music Assistant" \
    org.opencontainers.image.description="Music Assistant Server/Core" \
    org.opencontainers.image.source="https://github.com/music-assistant/server" \
    org.opencontainers.image.authors="The Music Assistant Team" \
    org.opencontainers.image.documentation="https://github.com/orgs/music-assistant/discussions" \
    org.opencontainers.image.licenses="Apache License 2.0" \
    io.hass.version="${MASS_VERSION}" \
    io.hass.type="addon" \
    io.hass.name="Music Assistant" \
    io.hass.description="Music Assistant Server/Core" \
    io.hass.platform="${TARGETPLATFORM}" \
    io.hass.type="addon"

VOLUME [ "/data" ]

ENTRYPOINT ["mass", "--config", "/data"]

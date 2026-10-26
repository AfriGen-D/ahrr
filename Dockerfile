# Container image for the AHRR scrub process.
#
# Bundles NCBI sra-human-scrubber (the `aligns_to` binary and its scripts).
# The k-mer database is NOT downloaded here and is NOT baked in: it is supplied
# per node and mounted or copied to /opt/scrubber/data/human_filter.db at
# deploy time. Keeping the database out of the image is what allows the image
# itself to be public.
FROM ubuntu:22.04

ARG SCRUBBER_VERSION=2.2.1
# The commit the tag above resolved to, verified with `git ls-remote --tags`:
#   refs/tags/2.2.1     ed90a1d29df0565635f558d03cc76e554e68b009
#   refs/tags/2.2.1^{}  70ac7409e7f4fa7ed8a7a489f7e5dd8716723e21
# A tag is mutable and can be moved or deleted upstream; a commit cannot.
ARG SCRUBBER_COMMIT=70ac7409e7f4fa7ed8a7a489f7e5dd8716723e21
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git python3 perl gzip pigz libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install sra-human-scrubber by commit, with no fallback.
#
# An earlier version fell back to cloning HEAD whenever the tagged clone
# failed -- a renamed upstream tag, or one bad minute of network -- and the
# resulting image was still labelled 2.2.1. That produces an image whose tag is
# a lie, and nothing in the build output says so.
#
# Fetching the commit directly also removes the tag as a trust anchor: an
# upstream force-move of 2.2.1 changes what a --branch clone gets, and changes
# nothing here. (GitHub serves this repository's commits to a shallow
# fetch-by-sha; not every host does.)
RUN git init /opt/scrubber \
    && git -C /opt/scrubber remote add origin https://github.com/ncbi/sra-human-scrubber.git \
    && git -C /opt/scrubber fetch --depth 1 origin ${SCRUBBER_COMMIT} \
    && git -C /opt/scrubber checkout --detach FETCH_HEAD \
    && test "$(git -C /opt/scrubber rev-parse HEAD)" = "${SCRUBBER_COMMIT}" \
    && printf '%s\n' "${SCRUBBER_COMMIT}" > /opt/scrubber/.source-commit \
    && rm -rf /opt/scrubber/.git
ENV PATH="/opt/scrubber/scripts:${PATH}"
ENV SCRUBBER_SOURCE_COMMIT=${SCRUBBER_COMMIT}

# So a running container can report what it contains, and a registry consumer
# can read it without pulling the layers.
LABEL org.opencontainers.image.authors="Aaron Berkman, Mamana Mbiyavanga, Shaun Aron, Scott Hazelhurst" \
      org.opencontainers.image.version="${SCRUBBER_VERSION}" \
      org.opencontainers.image.revision="${SCRUBBER_COMMIT}" \
      org.opencontainers.image.source="https://github.com/ncbi/sra-human-scrubber"

# Where the database is expected at runtime. Deliberately empty in the image:
# each deployment mounts or copies its own database to this path.
RUN mkdir -p /opt/scrubber/data
ENV SCRUBBER_DB=/opt/scrubber/data/human_filter.db

# Run as a non-root user. UID/GID 1000 is chosen to match the owner of the
# database on the underlying storage, so the process reads it through the owner
# bits rather than the world bits; see the securityContext note in
# nextflow.config. /opt/scrubber stays root-owned so the running process cannot
# rewrite its own tooling; only the writable paths are handed over.
RUN groupadd -g 1000 scrubber \
    && useradd -u 1000 -g 1000 -m -s /bin/bash scrubber \
    && mkdir -p /work \
    && chown scrubber:scrubber /work /opt/scrubber/data

WORKDIR /work
USER 1000

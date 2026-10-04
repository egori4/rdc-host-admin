FROM docker:29.7.2-cli@sha256:3f4743208d2338c934d7b8bcfbe1bb54c0b2355c510ad5e0f31c0c4a54bd704e AS docker-cli
FROM node:24-bookworm-slim@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6

LABEL org.opencontainers.image.title="RDC Host Admin" \
       org.opencontainers.image.description="Root-equivalent Desktop Commander remote administration for a native Linux Docker host" \
       org.opencontainers.image.source="https://github.com/egori4/rdc-host-admin" \
       io.egori4.project="rdc-host-admin" \
       io.egori4.security-profile="host-admin"

ENV NODE_ENV=production HOME=/root \
    NPM_CONFIG_UPDATE_NOTIFIER=false PUPPETEER_SKIP_DOWNLOAD=true \
    PATH=/opt/rdc/node_modules/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update  \
 && apt-get install -y --no-install-recommends \
       bash ca-certificates chromium fonts-liberation fonts-dejavu-core \
       curl wget jq git openssh-client python3 python3-pip python3-venv \
       procps util-linux iproute2 iputils-ping dnsutils netcat-openbsd \
       lsof less nano tar gzip unzip rsync file tini  \
 && rm -rf /var/lib/apt/lists/*

# Client binaries only. No nested Docker daemon, host package installs, or runtime npx downloads.
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
WORKDIR /opt/rdc
COPY package.json package-lock.json ./
RUN npm ci --omit=dev \
 && npm cache clean --force
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/hostsh /usr/local/bin/hostsh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh /usr/local/bin/hostsh  \
 && mkdir -p /var/lib/rdc-host-admin/device /var/lib/rdc-host-admin/config /var/lib/rdc-host-admin/workspace  \
 && chmod 0700 /var/lib/rdc-host-admin /var/lib/rdc-host-admin/device /var/lib/rdc-host-admin/config  \
 && ln -s /var/lib/rdc-host-admin/device /root/.desktop-commander-device  \
 && ln -s /var/lib/rdc-host-admin/config /root/.claude-server-commander  \
 && ln -s /var/lib/rdc-host-admin/workspace /workspace
USER 0:0
WORKDIR /workspace
# Host PID mode means tini is not PID 1: explicitly enable subreaper mode.
ENTRYPOINT ["/usr/bin/tini", "-s", "-g", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["desktop-commander", "remote"]

ARG VERSION=0.1.0
ARG VCS_REF=unknown
LABEL org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.revision="$VCS_REF"

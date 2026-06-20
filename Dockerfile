ARG TARGETARCH
FROM ghcr.io/home-assistant/amd64-base-debian:trixie

# Multi-arch variabelen
ARG TARGETOS
ARG TARGETARCH
ARG TARGETPLATFORM

# ===== build args voor extra tools =====
ARG EASY_ADD_VERSION
ARG ENTRYPOINT_DEMOTER_VERSION
ARG SET_PROPERTY_VERSION
ARG RESTIFY_VERSION
ARG MC_MONITOR_VERSION

# Tools installeren en up to date maken
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip jq
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-flask python3-waitress
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

# Installatie van box64 on arm
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      echo "🧱 Installing Box64 from Debian repository (arm64)..."; \
      set -eux; \
      apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends box64; \
      apt-get clean; \
      rm -rf /var/lib/apt/lists/*; \
    else \
      echo "Skipping Box64 installation for $TARGETARCH"; \
    fi

RUN echo "🏗️ Building for platform: ${TARGETPLATFORM} (OS=${TARGETOS}, ARCH=${TARGETARCH})"

# Default bedrock poort openen, en poort 8789 openen voor Ingress (Flask Webservice).
EXPOSE 19132/udp 8789/tcp

# Data volume en werkdirectory instellen
VOLUME ["/data"]
WORKDIR /data

ENTRYPOINT ["/usr/local/bin/entrypoint-demoter", "--match", "/data", "--debug", "--stdin-on-term", "stop", "/opt/start.sh"]

# Easy-add tool installeren
ADD https://github.com/itzg/easy-add/releases/download/${EASY_ADD_VERSION}/easy-add_linux_${TARGETARCH} /usr/local/bin/easy-add
RUN chmod +x /usr/local/bin/easy-add

# Extra tools installeren via easy-add
RUN easy-add --var version=${ENTRYPOINT_DEMOTER_VERSION} --var app=entrypoint-demoter --file {{.app}} --from https://github.com/itzg/{{.app}}/releases/download/v{{.version}}/{{.app}}_{{.version}}_linux_${TARGETARCH}.tar.gz
RUN easy-add --var version=${SET_PROPERTY_VERSION} --var app=set-property --file {{.app}} --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_linux_${TARGETARCH}.tar.gz
RUN easy-add --var version=${RESTIFY_VERSION} --var app=restify --file {{.app}} --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_linux_${TARGETARCH}.tar.gz
RUN easy-add --var version=${MC_MONITOR_VERSION} --var app=mc-monitor --file {{.app}} --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_linux_${TARGETARCH}.tar.gz

# Bestanden naar container kopiëren
COPY bedrock-entry.sh /opt/bedrock-entry.sh
COPY start.sh /opt/start.sh
COPY install-server.sh /opt/install-server.sh
COPY healthcheck.sh /opt/healthcheck.sh
COPY property-definitions.json /etc/bds-property-definitions.json
COPY web/app.py /opt/flask/app.py
COPY web/static /opt/flask/static
COPY bin/* /usr/local/bin/

# Prepare /opt/bds as an empty compatibility directory.
# The real BDS binary lives at /data/bds (persistent volume, written at runtime
# by install-server.sh). Symlinks for worlds/server.properties/allowlist/permissions
# are created by bedrock-entry.sh at each startup so they always point to /data.
RUN mkdir -p /opt/bds

# Maak scripts uitvoerbaar
RUN chmod +x /opt/bedrock-entry.sh
RUN chmod +x /opt/start.sh
RUN chmod +x /opt/install-server.sh
RUN chmod +x /opt/healthcheck.sh
RUN chmod +x /usr/local/bin/send-command

HEALTHCHECK --interval=15s --timeout=5s --retries=2 --start-period=15s CMD /opt/healthcheck.sh

# agent-browser — headed Playwright + official playwright-cli + noVNC for live viewing
# Base image pins system deps + OS; CLI brings its own playwright version and Chromium build.
FROM mcr.microsoft.com/playwright:v1.63.0-noble

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    NOVNC_PORT=6080 \
    VNC_PORT=5900 \
    NOVNC_HOME=/opt/novnc \
    ARTIFACTS_DIR=/artifacts \
    HOME=/home/pwuser \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PLAYWRIGHT_MCP_CONFIG=/app/.playwright/cli.config.json \
    PLAYWRIGHT_MCP_OUTPUT_DIR=/artifacts \
    PLAYWRIGHT_MCP_HEADLESS=false

# Display stack: Xvfb, openbox WM, x11vnc, noVNC deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb \
      openbox \
      x11vnc \
      x11-utils \
      x11-xserver-utils \
      curl \
      ca-certificates \
      git \
      python3 \
      python3-numpy \
      websockify \
    && rm -rf /var/lib/apt/lists/*

# noVNC
RUN git clone --depth 1 https://github.com/novnc/noVNC.git "${NOVNC_HOME}" \
    && git clone --depth 1 https://github.com/novnc/websockify.git "${NOVNC_HOME}/utils/websockify" \
    && ln -sf "${NOVNC_HOME}/vnc.html" "${NOVNC_HOME}/index.html" \
    && chown -R pwuser:pwuser "${NOVNC_HOME}"

WORKDIR /app

# Official Microsoft Playwright CLI (token-efficient agent control surface).
# Pin CLI release; install Chromium matching the CLI's playwright dependency into PLAYWRIGHT_BROWSERS_PATH.
RUN npm install -g @playwright/cli@0.1.20 \
    && cd "$(npm root -g)/@playwright/cli" \
    && npx playwright install chromium \
    && chmod -R a+rX /ms-playwright \
    && playwright-cli --help >/dev/null

# Default headed CLI config + thin wrapper
COPY config/cli.config.json /app/.playwright/cli.config.json
COPY scripts/pw /usr/local/bin/pw
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/pw \
    && mkdir -p /artifacts /home/pwuser/.playwright \
    && cp /app/.playwright/cli.config.json /home/pwuser/.playwright/cli.config.json \
    && chown -R pwuser:pwuser /app /artifacts /home/pwuser

USER pwuser

EXPOSE 6080

HEALTHCHECK --interval=15s --timeout=5s --start-period=25s --retries=3 \
  CMD-SHELL xdpyinfo -display :99 >/dev/null 2>&1 || exit 1

VOLUME ["/artifacts"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

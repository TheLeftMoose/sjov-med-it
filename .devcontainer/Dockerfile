FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG CLAUDE_CODE_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

USER vscode

RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}" \
    && /home/vscode/.local/bin/claude --version

USER root

RUN ln -s /home/vscode/.local/bin/claude /usr/local/bin/claude \
    && rm -rf /home/vscode/.claude /home/vscode/.claude.json

USER vscode

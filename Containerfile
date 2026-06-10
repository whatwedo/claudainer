FROM debian:stable-slim

RUN groupadd -g 1000 developer && \
    useradd -u 1000 -g developer -m -d /home/developer developer

COPY scripts/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh && /tmp/install.sh && rm /tmp/install.sh && \
    groupadd -f docker && \
    usermod -aG docker developer

ENV CLAUDE_CODE_DISABLE_AUTOUPDATER=1

USER developer
WORKDIR /workspace
CMD ["sleep", "infinity"]

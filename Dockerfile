FROM debian:stable-slim

RUN groupadd -g 1000 developer && \
    useradd -u 1000 -g developer -m -d /home/developer developer

COPY scripts/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh && /tmp/install.sh && rm /tmp/install.sh && \
    groupadd -f docker && \
    usermod -aG docker developer

# PTY wrapper that strips terminal mouse-tracking from a command's output.
# claudainer always runs Claude Code behind it so plain mouse selection/copy
# keeps working in the outer terminal (e.g. macOS Terminal.app).
COPY scripts/disable-mouse.js /usr/local/bin/claudainer-disable-mouse
RUN chmod +x /usr/local/bin/claudainer-disable-mouse

ENV DISABLE_AUTOUPDATER=1

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]

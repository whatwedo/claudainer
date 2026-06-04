FROM node:22-slim

RUN usermod -l developer -d /home/developer -m node && \
    groupmod -n developer node

COPY scripts/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh && /tmp/install.sh && rm /tmp/install.sh && \
    usermod -aG docker developer

USER developer
WORKDIR /workspace
CMD ["sleep", "infinity"]

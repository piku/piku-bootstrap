# E2E test image for piku-bootstrap with UV support
# Uses systemd-enabled Ubuntu for proper service management

FROM jrei/systemd-ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites for piku-bootstrap and testing
RUN apt-get update && apt-get install -y \
    curl \
    sudo \
    git \
    openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd

# Copy piku-bootstrap files from local checkout
COPY piku-bootstrap /root/piku-bootstrap
COPY playbooks /root/playbooks

RUN chmod 755 /root/piku-bootstrap

WORKDIR /root

# Copy test scripts
COPY tests/e2e-uv/test_uv_e2e.sh /root/test_uv_e2e.sh
RUN chmod 755 /root/test_uv_e2e.sh

# systemd needs to be PID 1
CMD ["/lib/systemd/systemd"]

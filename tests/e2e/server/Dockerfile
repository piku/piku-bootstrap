# Piku Server Dockerfile
FROM jrei/systemd-ubuntu:22.04

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    openssh-server \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (for Node.js app support)
# Using NodeSource to get a recent version
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install uv (for Python UV support)
# uv is a fast Python package installer that piku can use
# Install directly to /usr/local/bin so it's available to all users (including piku)
RUN curl -LsSf https://astral.sh/uv/install.sh | env CARGO_HOME=/usr/local UV_INSTALL_DIR=/usr/local/bin sh

# Configure SSH
RUN mkdir -p /var/run/sshd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config  
RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
RUN ssh-keygen -A

# Copy piku-bootstrap files to the location where the script expects them
# This prevents the script from cloning the upstream repo during first-run
RUN mkdir -p /root/.piku-bootstrap/piku-bootstrap
COPY piku-bootstrap /root/.piku-bootstrap/piku-bootstrap/piku-bootstrap
COPY playbooks /root/.piku-bootstrap/piku-bootstrap/playbooks

# Also keep a copy in /root for easy access
COPY piku-bootstrap /root/piku-bootstrap
RUN systemctl enable ssh

EXPOSE 22
CMD ["/lib/systemd/systemd"]

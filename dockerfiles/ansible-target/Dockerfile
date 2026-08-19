## Purpose: Local CI/CD provisioning-emulation harness Ansible target (sh/local-ci/*, task 4.x).
##   A bare Debian 12 host running systemd as PID 1 + sshd, standing in for a freshly-provisioned
##   EC2 instance so kit-modules/basis's real Ansible playbook (sh/ansible.sh -a playbook) can
##   converge against it. LOCAL EMULATION HARNESS ONLY — never part of the always-running app
##   stack (docker-compose.yml) or the on-demand toolkit stack (docker-compose.toolkit.yml), never
##   built/pushed via `make docker`/sh/system/docker.sh, and never published to a registry. Only
##   built/run by docker-compose.localci.yml, brought up by sh/local-ci/harness-up.sh.
## Notes:
## - systemd as PID 1 is required, not optional: kit-modules/basis's Ansible partials
##   05-setup-docker-log-rotation.yml (systemd: module) and 07-update-sshd-config.yml
##   (service:/service_facts) need a real init system to act on.
## - Do NOT bake secrets into the image (same rule as dockerfiles/iac/Dockerfile). The harness's
##   throwaway SSH public key is generated fresh on every `harness-up.sh` run into
##   kit-modules/basis/terraform/public_keys/ (git-ignored by basis itself, does not exist until
##   the harness is up) and is injected at container START by docker-entrypoint.sh from a
##   bind-mounted, read-only copy of that directory — never COPY'd at build time. This keeps the
##   image stable and reusable across every harness-up/down cycle (the key rotates every run; a
##   build-time COPY would force a rebuild every time) and matches this repo's existing
##   docker-entrypoint.sh convention (see .claude/rules/docker.md).

FROM debian:12

ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="starter-kit-ansible-target"
LABEL org.opencontainers.image.description="Local CI/CD harness only — bare Debian 12 + systemd SSH target for kit-modules/basis Ansible convergence. Never pushed to a registry."
LABEL org.opencontainers.image.vendor="SolidBunch"

# systemd as PID 1 + openssh-server + sudo + python3 (Ansible's default interpreter target).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       systemd \
       systemd-sysv \
       openssh-server \
       sudo \
       python3 \
       ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl enable ssh \
    # Standard systemd-in-Docker practice: mask units that are meaningless/misbehave without a
    # real console or udev-managed hardware.
    && systemctl mask systemd-udevd.service systemd-udev-trigger.service getty.target getty-static.service console-getty.service

# admin user with passwordless sudo. authorized_keys is populated at container START by
# docker-entrypoint.sh, not here — see the Dockerfile header comment.
RUN useradd -m -s /bin/bash admin \
    && echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin \
    && chmod 0440 /etc/sudoers.d/admin \
    && mkdir -p /home/admin/.ssh \
    && chmod 700 /home/admin/.ssh \
    && chown -R admin:admin /home/admin/.ssh \
    && touch /home/admin/.ssh/authorized_keys \
    && chmod 600 /home/admin/.ssh/authorized_keys \
    && chown admin:admin /home/admin/.ssh/authorized_keys

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# systemd's usual shutdown signal, so `docker stop` (compose stop/down) actually asks it to shut
# down cleanly instead of being SIGTERM-killed at the process-group level.
STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/lib/systemd/systemd"]

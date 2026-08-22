## Purpose: Reproducible IaC runner image (Terraform + Terragrunt + Ansible + AWS CLI + gcloud + SSH tools)
## Notes:
## - Pin tool versions for deterministic CI runs
## - Do NOT bake secrets into the image; mount them at runtime (env/volumes)
## - Terraform and Terragrunt are Go binaries: fetched in a native $BUILDPLATFORM stage and
##   COPY-ed in, never executed during build. Running them under QEMU on a foreign arch
##   crashes the Go runtime, which breaks multi-arch builds from an arm64 host.
##   Integrity is checked against the publishers' SHA256SUMS instead of a `--version` smoke test.

ARG DEBIAN_FRONTEND=noninteractive
ARG IMAGE_VERSION=1.1.1
ARG TF_VERSION=1.13.3
ARG TG_VERSION=0.87.1
ARG AWSCLI_VERSION=2.23.3
ARG ANSIBLE_PIP_VERSION=12.0.0

# Fetch stage — always runs on the builder's own architecture, no emulation.
# TARGETARCH still selects which architecture's binaries get downloaded.
FROM --platform=${BUILDPLATFORM} debian:12-slim AS fetch

ARG DEBIAN_FRONTEND
ARG TF_VERSION
ARG TG_VERSION
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

# Terraform (pinned) — multi-arch, checksum-verified
RUN set -e; \
    cd /tmp; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TARGETARCH}.zip" -o terraform.zip; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_SHA256SUMS" -o terraform.sums; \
    grep " terraform_${TF_VERSION}_linux_${TARGETARCH}.zip\$" terraform.sums \
      | sed "s| terraform_${TF_VERSION}_linux_${TARGETARCH}.zip\$| terraform.zip|" \
      | sha256sum -c -; \
    mkdir -p /out; \
    unzip -q terraform.zip -d /out; \
    chmod +x /out/terraform; \
    rm -f terraform.zip terraform.sums

# Terragrunt (pinned) — multi-arch, checksum-verified
RUN set -e; \
    cd /tmp; \
    curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v${TG_VERSION}/terragrunt_linux_${TARGETARCH}" -o terragrunt; \
    curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v${TG_VERSION}/SHA256SUMS" -o terragrunt.sums; \
    grep " terragrunt_linux_${TARGETARCH}\$" terragrunt.sums \
      | sed "s| terragrunt_linux_${TARGETARCH}\$| terragrunt|" \
      | sha256sum -c -; \
    mkdir -p /out; \
    mv terragrunt /out/terragrunt; \
    chmod +x /out/terragrunt; \
    rm -f terragrunt.sums


FROM debian:12-slim

ARG DEBIAN_FRONTEND
ARG IMAGE_VERSION
ARG TF_VERSION
ARG TG_VERSION
ARG AWSCLI_VERSION
ARG ANSIBLE_PIP_VERSION
ARG TARGETARCH

WORKDIR /workspace

LABEL org.opencontainers.image.title="starter-kit-iac"
LABEL org.opencontainers.image.description="IaC runner image with Terraform, Terragrunt, Ansible, AWS CLI, and gcloud"
LABEL org.opencontainers.image.vendor="SolidBunch"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL io.solidbunch.terraform.version="${TF_VERSION}"
LABEL io.solidbunch.terragrunt.version="${TG_VERSION}"
LABEL io.solidbunch.ansible.version="${ANSIBLE_PIP_VERSION}"
LABEL io.solidbunch.awscli.version="${AWSCLI_VERSION}"

# Base OS toolchain and Python for Ansible
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       unzip \
       git \
       jq \
       gnupg \
       lsb-release \
       openssh-client \
       rsync \
       python3 \
       python3-venv \
       bash \
       tar \
       adduser \
    && rm -rf /var/lib/apt/lists/*

# Terraform and Terragrunt — built in the native fetch stage above, not executed here
COPY --from=fetch /out/terraform /usr/local/bin/terraform
COPY --from=fetch /out/terragrunt /usr/local/bin/terragrunt

# AWS CLI v2 (pinned) — multi-arch
RUN set -e; \
    case "${TARGETARCH}" in \
      amd64) AWS_ZIP_ARCH=x86_64 ;; \
      arm64) AWS_ZIP_ARCH=aarch64 ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ZIP_ARCH}-${AWSCLI_VERSION}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Google Cloud SDK (apt repo; latest in that channel)
RUN mkdir -p /usr/share/keyrings \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Ansible (pinned) + cloud libs in isolated venv (avoid PEP 668)
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv ${VIRTUAL_ENV} \
    && ${VIRTUAL_ENV}/bin/pip install --no-cache-dir --upgrade pip \
    && ${VIRTUAL_ENV}/bin/pip install --no-cache-dir \
       "ansible==${ANSIBLE_PIP_VERSION}" \
       boto3 botocore
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# Default to bash shell; CI can override command/entrypoint
SHELL ["/bin/bash", "-lc"]

# Add entrypoint to drop privileges to host UID/GID
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]

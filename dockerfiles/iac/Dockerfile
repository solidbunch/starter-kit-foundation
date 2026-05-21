## Purpose: Reproducible IaC runner image (Terraform + Terragrunt + Ansible + AWS CLI + gcloud + SSH tools)
## Notes:
## - Pin tool versions for deterministic CI runs
## - Do NOT bake secrets into the image; mount them at runtime (env/volumes)

FROM debian:12-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG IMAGE_VERSION=1.1.0
ARG TF_VERSION=1.13.3
ARG TG_VERSION=0.87.1
ARG AWSCLI_VERSION=2.23.3
ARG ANSIBLE_PIP_VERSION=12.0.0
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

# Terraform (pinned) — multi-arch
RUN set -e; \
    case "${TARGETARCH}" in \
      amd64) TF_ZIP_ARCH=linux_amd64 ;; \
      arm64) TF_ZIP_ARCH=linux_arm64 ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${TF_ZIP_ARCH}.zip" -o /tmp/terraform.zip \
    && unzip -q /tmp/terraform.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/terraform \
    && rm -f /tmp/terraform.zip \
    && terraform -version

# Terragrunt (pinned) — multi-arch
RUN set -e; \
    case "${TARGETARCH}" in \
      amd64) TG_BIN_ARCH=linux_amd64 ;; \
      arm64) TG_BIN_ARCH=linux_arm64 ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v${TG_VERSION}/terragrunt_${TG_BIN_ARCH}" -o /usr/local/bin/terragrunt \
    && chmod +x /usr/local/bin/terragrunt \
    && terragrunt --version

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
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && aws --version

# Google Cloud SDK (apt repo; latest in that channel)
RUN mkdir -p /usr/share/keyrings \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/* \
    && gcloud --version

# Ansible (pinned) + cloud libs in isolated venv (avoid PEP 668)
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv ${VIRTUAL_ENV} \
    && ${VIRTUAL_ENV}/bin/pip install --no-cache-dir --upgrade pip \
    && ${VIRTUAL_ENV}/bin/pip install --no-cache-dir \
       "ansible==${ANSIBLE_PIP_VERSION}" \
       boto3 botocore \
    && ${VIRTUAL_ENV}/bin/ansible --version
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# Default to bash shell; CI can override command/entrypoint
SHELL ["/bin/bash", "-lc"]

# Add entrypoint to drop privileges to host UID/GID
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]

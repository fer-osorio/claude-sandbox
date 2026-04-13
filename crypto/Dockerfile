# ── claude-crypto
# Extends claude-base with the full cryptographic and HSM development stack:
#   OpenSSL (library + dev headers), p11-kit, SoftHSM2, GnuTLS utilities.
#
# SoftHSM2 setup details:
#   softhsm2 on Debian creates a group called "softhsm" and sets /var/lib/softhsm
#   to drwxr-x--- owned by softhsm:softhsm. Access requires group membership — the
#   same pattern as the host-level fix (see softhsm2-token-init-error.md).
#   claude-agent is added to "softhsm" here, not to "root", which would grant
#   far broader permissions than needed.
#
#   SOFTHSM2_CONF is declared as ENV (not a shell export) so it persists into
#   every subsequent layer and into the running container. Without it,
#   softhsm2-util silently falls back to a hardcoded path that may not exist,
#   producing: "ERROR: Failed to enumerate object store".
#
#   The config file is written explicitly so its content is auditable from
#   this Dockerfile rather than depending on whatever the package created.
#
#   The SO PIN and User PIN are for the development sandbox only.
#
# Build (after claude-base exists):
#   docker build --build-arg HOST_UID=$(id -u) -t claude-crypto ./crypto/
FROM claude-base

# ─────────────────────────────────────────────────────────────────────────────
# BUILD ARGUMENTS
# HOST_UID must be passed again — ARG values do not inherit across FROM.
# ─────────────────────────────────────────────────────────────────────────────
ARG HOST_UID=1000

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 1 — Cryptographic packages
# The softhsm2 package creates the "softhsm" group as a side effect of installation.
# That group is used for token directory permissions in LAYER 2.
# ─────────────────────────────────────────────────────────────────────────────
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    libssl-dev \
    p11-kit \
    p11-kit-modules \
    softhsm2 \
    gnutls-bin \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 2 — SoftHSM2 token initialization
# See header comment for the reasoning behind each decision.
# ─────────────────────────────────────────────────────────────────────────────
ENV SOFTHSM2_CONF=/etc/softhsm/softhsm2.conf

RUN mkdir -p /etc/softhsm \
    && printf 'directories.tokendir = /var/lib/softhsm/tokens/\nobjectstore.backend = file\nlog.level = ERROR\nslots.removable = false\n' \
       > /etc/softhsm/softhsm2.conf \
    && mkdir -p /var/lib/softhsm/tokens \
    && chown root:softhsm /var/lib/softhsm/tokens \
    && chmod 0770 /var/lib/softhsm/tokens \
    && softhsm2-util --init-token --slot 0 \
       --label "dev-token" \
       --so-pin 1234567890 \
       --pin 1234567890

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 3 — Group membership and user-scoped p11-kit config
# usermod runs as root, then we switch to claude-agent for the config file.
# p11-kit reads PKCS#11 module declarations from ~/.config/pkcs11/modules/.
# ─────────────────────────────────────────────────────────────────────────────
RUN usermod -aG softhsm claude-agent

USER claude-agent

RUN mkdir -p /home/claude-agent/.config/pkcs11/modules \
    && printf 'module: /usr/lib/softhsm/libsofthsm2.so\n' \
       > /home/claude-agent/.config/pkcs11/modules/softhsm2.module

CMD ["claude"]

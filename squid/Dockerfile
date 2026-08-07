FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818

RUN apt-get update && apt-get install -y --no-install-recommends squid \
    && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf

EXPOSE 3128

# Non-root execution (addition beyond the original guide — see SDD §6.4).
# "proxy" (uid/gid 13) is a base-passwd system account present in every
# Debian install; squid's own postinst defaults cache_effective_user to
# it. Confirmed against the bookworm squid 5.7-2+deb12u5 package's
# postinst script, not assumed.
USER proxy

CMD ["squid", "-N", "-f", "/etc/squid/squid.conf"]

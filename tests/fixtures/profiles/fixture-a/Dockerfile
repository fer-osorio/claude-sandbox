# Fixture profile for B-5 (docs/designs/0194-profile-composition.md,
# Decision 6). It follows the profile contract and leaves three traces a
# combination must keep: a root-owned marker, a command on an extended PATH,
# and the user it ends as.
ARG PARENT_IMAGE=claude-base
FROM ${PARENT_IMAGE}

USER root

RUN mkdir -p /opt/fixture-a/bin \
    && printf '#!/bin/sh\necho fixture-a\n' > /opt/fixture-a/bin/fixture-a \
    && chmod 0755 /opt/fixture-a/bin/fixture-a \
    && echo a > /etc/fixture-a.marker

ENV PATH=/opt/fixture-a/bin:${PATH}

USER claude-agent

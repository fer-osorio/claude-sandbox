# ── claude-research
# Extends claude-base with the LaTeX document preparation stack:
#   TeX Live (latex-extra, fonts-recommended, science), latexmk.
#
# Package choice:
#   texlive-latex-extra covers the vast majority of real-world documents and
#   papers. texlive-full (~5 GB) is available if you need obscure packages —
#   swap the package name and rebuild. texlive-science adds physics, maths,
#   and engineering packages (siunitx, physics, etc.).
#
# Python and SQLite are inherited from claude-base and are available here
# without any additional installation.
#
# Build (after claude-base exists):
#   docker build --build-arg HOST_UID=$(id -u) -t claude-research ./research/
FROM claude-base

# ─────────────────────────────────────────────────────────────────────────────
# BUILD ARGUMENTS
# HOST_UID must be passed again — ARG values do not inherit across FROM.
# ─────────────────────────────────────────────────────────────────────────────
ARG HOST_UID=1000

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 1 — LaTeX packages
# latexmk automates the multi-pass compilation that LaTeX documents often
# require (running pdflatex + bibtex + pdflatex + pdflatex, etc.).
# ─────────────────────────────────────────────────────────────────────────────
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-latex-extra \
    texlive-fonts-recommended \
    texlive-science \
    latexmk \
    && rm -rf /var/lib/apt/lists/*

USER claude-agent

CMD ["claude"]

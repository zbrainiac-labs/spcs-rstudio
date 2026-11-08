# RStudio Server for Snowpark Container Services
# Based on rocker/rstudio (open-source R + RStudio Server).
# The versioned rocker tag also pins CRAN to a dated Posit Package Manager
# snapshot, so install2.r below resolves reproducible package versions.

ARG ROCKER_VERSION=4.6.2
# Multi-arch: linux/arm64 (SPCS GEN_ARM_G1_*, Apple Silicon) and linux/amd64.
# The platform comes from --platform / buildx; TARGETARCH selects the driver.
FROM rocker/rstudio:${ROCKER_VERSION} AS runtime

ARG TARGETARCH
ARG SNOWFLAKE_ODBC_VERSION=4.3.0
ARG SNOWFLAKE_ODBC_SHA256_AMD64=79dffec20601d2f2b58b1eabd79da4022f5dcc1536d799912c96c4b62a0f146a
ARG SNOWFLAKE_ODBC_SHA256_ARM64=47248599e2979779ee145de79c0d788d0ba12dc78749834a457abdfdee7ece4e

LABEL org.opencontainers.image.title="spcs-rstudio" \
      org.opencontainers.image.description="RStudio Server with Snowflake ODBC for Snowpark Container Services" \
      org.opencontainers.image.source="https://github.com/zbrainiac-labs/spcs-rstudio" \
      org.opencontainers.image.licenses="Apache-2.0"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System dependencies, the Snowflake ODBC driver (pinned version, checksum
# verified per architecture) and R packages in one layer
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
        unixodbc \
        unixodbc-dev \
        odbcinst \
        curl \
        ca-certificates \
        nginx \
        gettext-base \
    && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default \
    && LIBDIR="/usr/lib/$(uname -m)-linux-gnu" \
    && ln -sf "$LIBDIR/libodbcinst.so.2" "$LIBDIR/libodbcinst.so.1" \
    && case "${TARGETARCH}" in \
      amd64) REPO=linux;        PKG=x86_64;  SHA="${SNOWFLAKE_ODBC_SHA256_AMD64}" ;; \
      arm64) REPO=linuxaarch64; PKG=aarch64; SHA="${SNOWFLAKE_ODBC_SHA256_ARM64}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /tmp/snowflake-odbc.deb \
        "https://sfc-repo.snowflakecomputing.com/odbc/${REPO}/${SNOWFLAKE_ODBC_VERSION}/snowflake-odbc-${SNOWFLAKE_ODBC_VERSION}.${PKG}.deb" \
    && echo "${SHA}  /tmp/snowflake-odbc.deb" | sha256sum -c - \
    && dpkg -i /tmp/snowflake-odbc.deb \
    && rm /tmp/snowflake-odbc.deb \
    && install2.r --error --skipinstalled DBI odbc dplyr dbplyr ggplot2 tidyr \
    && rm -rf /tmp/downloaded_packages

# nginx on :8787 in front of RStudio (:8788, localhost only): admits only
# RSTUDIO_ALLOWED_USER and hands the SPCS caller token to R (caller's rights)
COPY --chmod=0755 docker/services.d/rstudio/run /etc/services.d/rstudio/run
COPY docker/nginx/rstudio.conf.template /etc/nginx/templates/rstudio.conf.template
COPY --chmod=0755 docker/services.d/nginx/run /etc/services.d/nginx/run
COPY --chmod=0755 docker/services.d/caller-token-trim/run /etc/services.d/caller-token-trim/run

# Connection helper and examples in the default RStudio home directory
COPY --chown=rstudio:rstudio R/connect.R /home/rstudio/connect.R
COPY --chown=rstudio:rstudio R/examples/snowflake_test.R /home/rstudio/snowflake_test.R
COPY --chown=rstudio:rstudio R/examples/helloworld.R /home/rstudio/helloworld.R

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fs http://localhost:8787/healthz > /dev/null || exit 1

# Test stage: runtime + test tooling; never deployed (docker build --target test)
FROM runtime AS test
RUN install2.r --error --skipinstalled testthat covr xml2 lintr \
    && rm -rf /tmp/downloaded_packages
COPY .lintr /src/.lintr
COPY R/ /src/R/
COPY tests/testthat/ /src/tests/testthat/
COPY tests/lint_r.R /src/tests/lint_r.R
WORKDIR /src
ENV CONNECT_R_DIR=/src/R

# Default build target is the runtime image
FROM runtime AS final

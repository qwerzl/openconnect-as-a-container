# Alpine version
ARG ALPINE_VERSION=3.17.3
# 3proxy version
ARG THREE_PROXY_REPO=https://github.com/3proxy/3proxy
ARG THREE_PROXY_BRANCH=0.9.4
ARG THREE_PROXY_URL=${THREE_PROXY_REPO}/archive/${THREE_PROXY_BRANCH}.tar.gz

# Build 3proxy
FROM alpine:${ALPINE_VERSION} as builder
ARG THREE_PROXY_REPO
ARG THREE_PROXY_BRANCH
ARG THREE_PROXY_URL
ADD ${THREE_PROXY_URL} /${THREE_PROXY_BRANCH}.tar.gz

RUN apk add --update \
      alpine-sdk \
      bash \
      linux-headers \
      xz \
      curl \
    && cd / \
    && tar -xf ${THREE_PROXY_BRANCH}.tar.gz \
    && cd 3proxy-${THREE_PROXY_BRANCH} \
    && make -f Makefile.Linux \
    && mkdir /root-out


# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.1.4.2"

# add s6 overlay
RUN S6_OVERLAY_URL_PREFIX="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}" \
    && S6_OVERLAY_ARCH="$(uname -m)" \
    && S6_OVERLAY_NOARCH_TAR_FILE="s6-overlay-noarch.tar.xz" \
    && S6_OVERLAY_ARCH_TAR_FILE="s6-overlay-${S6_OVERLAY_ARCH}.tar.xz" \
    && S6_OVERLAY_NOARCH_URL="${S6_OVERLAY_URL_PREFIX}/${S6_OVERLAY_NOARCH_TAR_FILE}" \
    && S6_OVERLAY_ARCH_URL="${S6_OVERLAY_URL_PREFIX}/${S6_OVERLAY_ARCH_TAR_FILE}" \
    && S6_OVERLAY_SYMLINKS_NOARCH_TAR_FILE=s6-overlay-symlinks-noarch.tar.xz \
    && S6_OVERLAY_SYMLINKS_ARCH_TAR_FILE=s6-overlay-symlinks-arch.tar.xz \
    && S6_OVERLAY_SYMLINKS_NOARCH_URL="${S6_OVERLAY_URL_PREFIX}/${S6_OVERLAY_SYMLINKS_NOARCH_TAR_FILE}" \
    && S6_OVERLAY_SYMLINKS_ARCH_URL="${S6_OVERLAY_URL_PREFIX}/${S6_OVERLAY_SYMLINKS_ARCH_TAR_FILE}" \
    && echo "Downloading from ${S6_OVERLAY_NOARCH_URL} and ${S6_OVERLAY_ARCH_URL}" \
    && curl -L ${S6_OVERLAY_NOARCH_URL} -o /tmp/${S6_OVERLAY_NOARCH_TAR_FILE} \
    && curl -L ${S6_OVERLAY_ARCH_URL} -o /tmp/${S6_OVERLAY_ARCH_TAR_FILE} \
    && curl -L ${S6_OVERLAY_SYMLINKS_NOARCH_URL} -o /tmp/${S6_OVERLAY_SYMLINKS_NOARCH_TAR_FILE} \
    && curl -L ${S6_OVERLAY_SYMLINKS_ARCH_URL} -o /tmp/${S6_OVERLAY_SYMLINKS_ARCH_TAR_FILE} \    
    && tar -C /root-out -Jxpf /tmp/${S6_OVERLAY_NOARCH_TAR_FILE} \
    && tar -C /root-out -Jxpf /tmp/${S6_OVERLAY_ARCH_TAR_FILE} \
    && tar -C /root-out -Jxpf /tmp/${S6_OVERLAY_SYMLINKS_NOARCH_TAR_FILE} \    
    && tar -C /root-out -Jxpf /tmp/${S6_OVERLAY_SYMLINKS_ARCH_TAR_FILE} \
    && echo "Download latest vpnc-script" \
    && VPN_SCRIPT_URL="https://gitlab.com/openconnect/vpnc-scripts/raw/master/vpnc-script" \
    && mkdir -p /root-out/etc/vpnc \
    && curl -L ${VPN_SCRIPT_URL} -o /root-out/etc/vpnc/vpnc-script

ADD rootfs /root-out
RUN chmod +x /root-out/opt/utils/healthcheck.sh \
    && chmod +x /root-out/etc/services.d/*/run \
    && chmod +x /root-out/etc/vpnc/vpnc-script \
    && chmod +x /root-out/etc/cont-init.d/01-contcfg \
    && chmod +x /root-out/etc/cont-init.d/30-occfg

FROM alpine:${ALPINE_VERSION}
ARG THREE_PROXY_BRANCH

# openconnect >= 9.20 is required for Cisco "strap" / SSPKI key-bound sessions
# (e.g. UCLA Bruin VPN — the SSO cookie carries an openconnect_strapkey the
# client must present on connect). Alpine's package lags (<= 9.12, no strap),
# so build openconnect from source.
ARG OPENCONNECT_VERSION=9.21

RUN apk upgrade --update --no-cache \
    && apk --update --no-cache add \
        bash \
        tzdata \
        dnsmasq \
        gnutls \
        libxml2 \
        zlib \
    && apk --no-cache add --virtual .oc-build \
        build-base curl pkgconf gnutls-dev libxml2-dev zlib-dev linux-headers \
    && curl -fL "https://www.infradead.org/openconnect/download/openconnect-${OPENCONNECT_VERSION}.tar.gz" -o /tmp/oc.tar.gz \
    && mkdir -p /tmp/oc \
    && tar -xf /tmp/oc.tar.gz -C /tmp/oc --strip-components=1 \
    && cd /tmp/oc \
    && ./configure --prefix=/usr \
        --with-vpnc-script=/etc/vpnc/vpnc-script \
        --disable-nls --without-libpcsclite --without-gssapi \
        --without-libproxy --without-stoken --without-libp11 \
    && make -j"$(nproc)" \
    && make install \
    && cd / \
    && rm -rf /tmp/oc /tmp/oc.tar.gz \
    && apk del .oc-build \
    && rm -rf /var/cache/apk/* \
    && openconnect --version | head -1

COPY --from=builder /3proxy-${THREE_PROXY_BRANCH}/bin /usr/local/bin
COPY --from=builder /root-out /

# Init
ENTRYPOINT [ "/init" ]

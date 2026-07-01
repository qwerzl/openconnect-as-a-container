# AnyConnect, Pulse and PAN container with proxies
## Changelog

- v20260701b: Build openconnect **v9.21** from source instead of the Alpine package (which lags at v9.12). Required for Cisco **strap / SSPKI** key-bound sessions — the SSO cookie carries an `openconnect_strapkey` the client must present on connect, so the fetch-side and container openconnect must both support strap (>= ~v9.20). Without it the tunnel connect returns `HTTP/1.1 401 Unauthorized` ("Cookie was rejected by server"). Override with `--build-arg OPENCONNECT_VERSION=`.
- v20260701: Add SAML/SSO (Shibboleth) support via `AUTH_MODE=cookie`. A session cookie obtained on a machine with a browser (e.g. `openconnect --external-browser=open --cookieonly`) is written to `/vpn/token` and fed to openconnect with `--cookie-on-stdin`. Add a configurable `USER_AGENT`. Needed for head-ends that have disabled plain username/password auth (e.g. UCLA Bruin VPN).
- v20230405: Add an override OpenSSL3 configuration to get around `routines::unsafe legacy renegotiation disabled` error.
- v20230402: Update to `s6-overlay` version 3. Latest [`vpnc-script`](https://gitlab.com/openconnect/vpnc-scripts)
- v20220603: Add a `build.sh` script. Set s6-overlay version to 2.2.0.3. Update to version 3 pending.
- v20210813: Fix mount vpnpassd typo in `docker-compose.yml`. Add a note regarding password editing with `vim.`
- v20210405: Set dynamic token through mounted file to `/vpn/token` for 2FA users. Rename `PASSWORD1` and `PASSWORD2` to `PASSWORD` and `TOKEN`, respectively. Add `dnsmasq`.
- v20201208: Replace `brook` + `ufw` combo with `3proxy`. Reduce image size significantly.
- v20201116: Enable IPv6to4 fallback.
- v20201109: Use `s6-overlay` instead of `runit`. This change allow setting an environment variable through a file via prefix `FILE__`.
- v20200115: Use `brook` for SOCKS5 instead of HTTP on `privoxy`.
- v20190924: Initial version.

![openconnect](vpncontainer.png)

An [s6-overlay](https://github.com/just-containers/s6-overlay)ed Alpine Linux container with:

- VPN connection to your corporate network via [`openconnect`](https://github.com/openconnect). `openconnect` can connect to AnyConnect, Pulse and PAN.
- Proxy server with [3proxy](https://github.com/z3APA3A/3proxy)
- [`dnsmasq`](https://thekelleys.org.uk/dnsmasq/doc.html) to resolve internal domains.
- The container starts in [`privileged`](https://docs.docker.com/engine/reference/run/#runtime-privilege-and-linux-capabilities) mode in order to avoid the `read-only file system` [error](https://serverfault.com/questions/878443/when-running-vpnc-in-docker-get-cannot-open-proc-sys-net-ipv4-route-flush). Please proceed with your own **risk**.

## Build

### Build the image

Use `build.sh` with an `s6-overlay` version. This version parameter is optional.

```Shell
sh build.sh 3.1.4.2
```

Or, build the image with `docker` with BuiltKit enabled:

```Shell
DOCKER_BUILDKIT=1 docker build --build-arg S6_OVERLAY_VERSION="3.1.4.2" -t ducmthai/openconnect:latest .
```

Alternatively, use `docker-compose build`:
```Shell
COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 docker-compose build --build-arg S6_OVERLAY_VERSION="3.1.4.2"
```

## Starting the VPN Proxy

### `vpn.config`

The main configuration file, contain the following values:

- `SERVER`: VPN endpoint
- `USERNAME`: Login username
- `PASSWORD`: Login primary password
- `DYNAMIC_TOKEN`: `true` if dynamic OTP is required, `false` otherwise.
- `PROXY_USER`: Proxy username (optional).
- `PROXY_PASS`: Proxy password.
- `KEEP_ALIVE_ENDPOINT`: An endpoint (can be internal or external) to keep the VPN connection alive
- `AUTH_MODE`: `password` (default) or `cookie`. See [SAML / SSO (cookie) mode](#saml--sso-cookie-mode).
- `USER_AGENT`: User-Agent openconnect presents to the head-end. Defaults to `AnyConnect Windows 4.10.05111`. Some SSO/SAML gateways only offer the browser (Shibboleth) login flow to a recognised client UA.

### Environment variables

The environment variables needed for exposing the proxy to the local network:

- `PROXY_PORT`: If set, the SOCKS5 proxy is enabled and exposed through this port
- `HTTP_PROXY_PORT`: If set, the HTTP proxy is enabled and exposed through this port
- `LOCAL_NETWORK`: The CIDR mask of the local IP addresses (e.g. 192.168.0.1/24, 10.1.1.0/24) which will be acessing the proxy. This is so the response to a request can be returned to the client (i.e. your browser).
- `OPENSSL_CONF`: Custom OpenSSL3 configuration. Default value is `/etc/ssl/openssl.cnf`. This custom configuraton helps avoiding `routines::unsafe legacy renegotiation disabled` error with certain corporate VPN setups. If you don't want `UnsafeLegacyRenegotiation`, simply remove or comment out this variable. [Reference](https://github.com/dotnet/dotnet-docker/issues/4332).
- `EXT_IP`: Your external IP. Used only for healthcheck. You can get your current external IP on [ifconfig.co](https://ifconfig.co/ip)

These variables can be specified in the command line or in the `.env` file in the case of `docker-compose`.

### Set password in a file

Passwords can be set using a `FILE__` prefixed environment variable where its value is path to the file contains the password:

```Shell
FILE__PASSWORD=/vpn/passwd
```

### Create a docker network
Before starting the container, please create a docker network for it:

```Shell
docker network create openconnect --subnet=10.30.0.1/16
```
### Start with `docker run`

```Shell
docker build -t ducmthai/openconnect .
docker run -d \
--cap-add=NET_ADMIN \
--device=/dev/net/tun \
--name=vpn_proxy \
--dns=1.1.1.1 --dns=1.0.0.1 \
--privileged=true \
--restart=always \
-e "PROXY_PORT=3128" \
-e "HTTP_PROXY_PORT=3129" \
-e "LOCAL_NETWORK=192.168.0.1/24" \
-e "FILE__PASSWORD=/vpn/passwd" \
-e "OPENSSL_CONF=/etc/ssl/openssl.cnf" \
-e "EXT_IP=<get_yours_at_ifconfig.co/ip> \
-v /etc/localtime:/etc/localtime:ro \
-v "$(pwd)"/vpn.config:/vpn/vpn.config:ro \
-v "$(pwd)"/vpnpasswd:/vpn/passwd:ro \
-v "$(pwd)"/vpntoken:/vpn/token \
-p 3128:3128 \
-p 3129:3129 \
ducmthai/openconnect:latest
```

### Start with `docker-compose`

A `docker-compose.yml` file is also provided:

```Shell
docker-compose up -d
```

### Supplying token
Token is taken from the file `/vpn/token` within the container. If `DYNAMIC_TOKEN` is `true` then the container clears the file after reading. To supply the dynamic OTP, simply do this outside the container:

```Shell
echo OTP_HERE > ./vpntoken
```

## SAML / SSO (cookie) mode

Some head-ends have disabled plain username/password login and hand clients off
to a SAML IdP / Shibboleth SSO flow in a browser (e.g. **UCLA Bruin VPN**,
`ssl.vpn.ucla.edu`). openconnect cannot complete an interactive browser login
from inside a headless container, so this image supports feeding it a
**pre-obtained session cookie** instead.

Set `AUTH_MODE=cookie` in `vpn.config`. The `openconnect` service then waits for
a cookie to appear in `/vpn/token` and connects with `--cookie-on-stdin`
(`USERNAME`/`PASSWORD` are ignored in this mode).

### 1. Obtain a cookie on a machine with a browser

Install openconnect v9+ locally (`brew install openconnect`, `apt install
openconnect`, …) and run, using the **same** `USER_AGENT` as the container:

```Shell
openconnect --protocol=anyconnect \
  --useragent='AnyConnect Windows 4.10.05111' \
  --external-browser=open --cookieonly \
  ssl.vpn.ucla.edu
```

Your browser opens the SSO login (university logon + MFA). On success,
openconnect prints **only the session cookie** to stdout (`--cookieonly` means
it authenticates without connecting, so no root/sudo is needed).

### 2. Deliver the cookie to the container

Pipe it straight into `vpntoken` (keeps it off your clipboard):

```Shell
openconnect --protocol=anyconnect \
  --useragent='AnyConnect Windows 4.10.05111' \
  --external-browser=open --cookieonly ssl.vpn.ucla.edu \
  | ssh user@your-server 'cat > /path/to/vpntoken'
```

The container picks the cookie up within ~2s, brings up `tun0`, and the proxies
start serving. Re-run when the session expires.

> **Note on client-IP binding:** some Cisco head-ends tie the session to the IP
> that performed the SSO login, so a cookie fetched on your laptop is rejected
> (`HTTP/1.1 401 Unauthorized`, "Cookie was rejected by server") when the
> container connects from the server's IP. Fix: make openconnect's control
> connection egress from the server. Open an SSH SOCKS proxy through the server
> (`ssh -D 1080 -N user@server`) and add `--proxy socks5://127.0.0.1:1080` to
> the `--cookieonly` command; the resulting cookie is then bound to the server's
> IP. Complete the browser SSO as usual.

## Connecting to the VPN Proxy

Set your proxy to socks5://127.0.0.1:${PROXY_PORT}. Use Socks5 username and password if set.

## Tested environments
- Raspberry Pi 4 B+ (4GB model)
- WSL 2 + Docker WSL2 + Proxifier
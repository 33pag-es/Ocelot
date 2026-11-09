# Ocelot

Ocelot is a BitTorrent tracker written in C++ for the [Gazelle](http://github.com/OPSnet/Gazelle) project.
It supports requests over TCP and can only track IPv4 peers.

## Ocelot Compile-time Dependencies

* [CMake](https://cmake.org/) (3.12+ required)
* [GCC/G++](http://gcc.gnu.org/) (12+ recommended) or [Clang](https://clang.llvm.org/) (5+ minimum)
* [Boost](http://www.boost.org/) (1.66+ required for `boost::asio::io_context`)
* [libev](http://software.schmorp.de/pkg/libev.html) (4.0+ required)
* [libfmt](https://github.com/fmtlib/fmt) (8.1+ required)
* [MySQL++](http://tangentsoft.net/mysql++/) (3.2.0+ required)
* [xxHash](https://github.com/Cyan4973/xxHash) (0.8+ development headers)
* [MySQL Client](https://dev.mysql.com/downloads/c-api/) (8.0+ recommended)
* [jemalloc](http://jemalloc.net/) (5.0+ optional, but strongly recommended)
* [TCMalloc](http://goog-perftools.sourceforge.net/doc/tcmalloc.html) (optional, alternative to jemalloc)

## Installation

### Debian Bookworm
```bash
sudo apt-get install \
    build-essential \
    cmake \
    default-libmysqlclient-dev \
    libboost-iostreams-dev \
    libboost-system-dev \
    libev-dev \
    libfmt-dev \
    libjemalloc-dev \
    libmysql++-dev \
    libxxhash-dev \
	netcat-traditional \
    pkg-config
cmake . -B build
make -C build
```

The [Gazelle installation guides](https://github.com/WhatCD/Gazelle/wiki/Gazelle-installation) include instructions for installing Ocelot as a part of the Gazelle project.

### Docker

```bash
docker build . -t ocelot
docker run -v $(pwd)/ocelot.conf:/srv/ocelot.conf ocelot
```

### Production tracker server

`docker-compose.prod.yml` runs Ocelot on its own server, joined to the
Gazelle site server by a WireGuard tunnel (site `10.33.0.1`, this server
`10.33.0.2`). Over the tunnel only, Ocelot uses MySQL on the site server,
Gazelle calls Ocelot on `TRACKER_TUNNEL_IP:34000`, and Ocelot calls
Gazelle's freeleech-token callback at `GAZELLE_HOST:GAZELLE_PORT`. Caddy on
this server serves the public announce URL.

1. WireGuard: copy `docker/wg0.conf.example` to `/etc/wireguard/wg0.conf`,
   fill it in, and `systemctl enable --now wg-quick@wg0`.
2. Start Docker after the tunnel. A port bound to the tunnel address fails
   if `wg0` does not exist yet, and Docker does not retry it:

   ```bash
   mkdir -p /etc/systemd/system/docker.service.d
   printf '[Unit]\nWants=wg-quick@wg0.service\nAfter=wg-quick@wg0.service\n' \
       > /etc/systemd/system/docker.service.d/wireguard.conf
   systemctl daemon-reload
   ```

3. Configure and start Ocelot:

   ```bash
   cp .env.example .env    # fill in every value
   docker compose -f docker-compose.prod.yml up -d --build
   ```

4. Caddy: copy `docker/Caddyfile.example` to `/etc/caddy/Caddyfile`, set
   the tracker hostname, and reload. The tracker hostname is an A record
   (no AAAA; DNS-only on Cloudflare). Caddy exposes only
   `/<passkey>/announce` and `/<passkey>/scrape` and refuses IPv6 peers.
5. Firewall: SSH; `80/tcp` and `443/tcp` from anywhere; `51820/udp` from
   the site server's public IP. Docker-published ports bypass ufw, which is
   why Ocelot is bound only to loopback and the tunnel address.

`.env` must match the site server: `OCELOT_MYSQL_USER`/`OCELOT_MYSQL_PASSWORD`
as in its `.env`, and the 32-character `TRACKER_SECRET`/`TRACKER_REPORTKEY`
as in its `lib/override.config.php`, where `TRACKER_HOST` is this server's
tunnel IP. The site's MySQL creates the Ocelot account with per-table grants
matching the queries in `src/db.cpp`, including `DROP` on `xbt_files_users`
for the startup `TRUNCATE`, and accepts it only from this server's tunnel IP.

`GAZELLE_PORT` must be a number: the image has no `/etc/services`, so a
service name such as `http` does not resolve. Ocelot trusts
`X-Forwarded-For`, so keep it on loopback behind Caddy; set
`OCELOT_IGNORE_XFF=1` only if port 34000 is published directly. Set
`OCELOT_IMAGE` to use a prebuilt image instead of building this checkout.

### Standalone Installation

* Build the binary

        cmake . -B build && make -C build

(Technically there is no need to run cmake if there are no library changes, but it is instant).

* Create the following tables according to the [Gazelle database schema](https://raw.githubusercontent.com/WhatCD/Gazelle/master/gazelle.sql):
 - `torrents`
 - `torrents_leech_stats`
 - `users_freeleeches`
 - `users_leech_stats`
 - `users_main`
 - `xbt_client_whitelist`
 - `xbt_files_users`
 - `xbt_snatched`

* Edit `ocelot.conf` to your liking.

## Running Ocelot

### Run-time options:

* `-c <path/to/ocelot.conf>` - Path to config file. If unspecified, the current working directory is used.
* `-d` or `--daemonize` - Run as a daemon in the background.
* `-v` - Print queue status every time a flush is initiated.
* `-V` or `--version` - Print the version
* `-X` or `--ignore-xff` - Ignore the X-Forwarded-For header

### Notes:

By default, ocelot will trust X-Forwarded-For headers as the source for client
IP addresses. If ocelot is running behind a proxy, this is the desired behavior.
(And if it is not, how are you performing SSL termination?)

If, for whatever reason, ocelot is not behind a proxy, this would allow an
attacker to insert a bogus X-Forwarded-For header and set the IP address to a
different IP address under their control. The `--ignore-xff` flag prevents this.

You can run a test ocelot daemon alongside a production daemon by specifying
a separate configuration file, and setting `readonly = true`. This will
prevent the database peer tables from being reset.

### Signals

* `SIGHUP` - Reload config
* `SIGUSR1` - Reload torrent list, user list and client whitelist

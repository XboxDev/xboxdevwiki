---
name: verify
description: Build the xboxdevwiki image and drive the running container (wiki features, uploads, startup decryption) to verify a change.
---

# Verifying xboxdevwiki

The surface is the container's HTTP port. Build the image, run it against a
scratch database, and drive it with curl or a browser. Never point a test at the
live database (the default when `WG_DB_SERVER` is unset) or run `deploy`.

## Build and run

```sh
export NIX_CONFIG=$'extra-substituters = https://filc.cachix.org\nextra-trusted-public-keys = filc.cachix.org-1:8rA7kXyu1HaJuMTsAKfA9fU/+r8YtLv5KiZ5hfDNZMk='
$(nix-build -A image) | docker load          # prints the image name
```

The build itself fails if anything in the image is not built with Fil-C; the
tally is the last line of `$(nix-build -A image.rootfs)/nix-support/rootfs.log`.

Scratch database: `nix-build -E '(import ./nix/filc.nix {}).pkgs.mariadb'`, then
`mariadb-install-db` and `mariadbd` on a spare port. Create the schema by
running `maintenance/install.php` from a copy of `mediawiki/htdocs` *without*
`LocalSettings.php` (it refuses otherwise), with database `bitnami_mediawiki` and
user `bn_mediawiki`.

```sh
docker run -d --name wiki --network host --read-only --tmpfs /tmp:mode=1777 \
  --memory 1g --cpus 1 \
  -e WG_DB_SERVER=127.0.0.1:3307 -e WG_DB_PASSWORD=... -e WG_SECRET_KEY=... \
  -e GCS_ACCESS_KEY=... -e GCS_SECRET_KEY=... IMAGE
```

To change settings for a test, bind-mount an edited `LocalSettings.php` over
`$(nix-instantiate --eval --raw -A image.mediawiki)/LocalSettings.php`.

## Flows worth driving

- Log in and edit through `api.php`; view a page with `<syntaxhighlight line>`,
  `<ref>` and a table. `docker logs` should hold nothing but "server started".
- Upload PNG, JPEG and GIF and embed them as thumbnails. Stand in for GCS with
  `versitygw --virtual-domain s3.test:9000 posix DIR`, `--add-host` for `s3.test`
  and `xboxdevwiki-images.s3.test`, and the endpoint edited in LocalSettings.
- Conflicting edits by two *different* users (`basetimestamp`) exercise diff3.
- Private files must come back as wiki titles, never as content or PHP output:
  `/maintenance/tables.sql`, `/index.php/../mw-config/index.php`,
  `/extensions/Nuke/Nuke.php/x.css`.
- Start with none of the four secrets set, `--add-host` `metadata.google.internal`
  and `cloudkms.googleapis.com` to mock servers, and a test CA mounted over the
  `curl.cainfo` path. Try 403, 503 and an untrusted certificate too.
- Cold start under load: queue jobs with API edits, `docker restart`, then a few
  hundred mixed requests at concurrency 8. Anything but HTTP 200 is a finding.

## Gotchas

- The image has no grep, sed or find. `docker exec wiki php ...` runs
  maintenance scripts.
- It runs as `nobody`: it cannot read bind mounts under a 0700 directory.
- MediaWiki skips the merge when both conflicting edits are by the same user.
- API requests do not run queued jobs; `index.php` page views do.
- On a non-default port, MediaWiki's self-requests get 400 from lighttpd (it
  drops the port from `Host`). That is the test's port, not a bug in the image.

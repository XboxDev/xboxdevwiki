# xboxdevwiki

The MediaWiki behind [xboxdevwiki.net](https://xboxdevwiki.net), built with Nix
into a container for Cloud Run. Everything in the image is compiled with
[Fil-C](https://fil-c.org); the build fails if something is not.

```sh
nix run -f . deploy                      # build, push, release on Cloud Run
$(nix-build -A image) | docker load      # just build the image
```

Use the binary cache, or Nix will build the Fil-C compiler from source:

```ini
extra-substituters = https://filc.cachix.org
extra-trusted-public-keys = filc.cachix.org-1:8rA7kXyu1HaJuMTsAKfA9fU/+r8YtLv5KiZ5hfDNZMk=
```

## Running it locally

```sh
docker run --rm -p 8080:8080 \
  -e WG_DB_SERVER=host:3306 -e WG_DB_PASSWORD=... -e WG_SECRET_KEY=... \
  -e GCS_ACCESS_KEY=... -e GCS_SECRET_KEY=... \
  us-central1-docker.pkg.dev/xqemu-154113/xboxdevwiki/xboxdevwiki:$(nix-instantiate --eval --raw -A image.imageTag)
```

`WG_DB_SERVER` is needed: the live database takes no connections from outside
Cloud Run.

## Secrets

`nix/secrets.nix` holds them encrypted with Cloud KMS. The container decrypts
them when it starts, as the `xboxdevwiki` service account, which has
`roles/cloudkms.cryptoKeyDecrypter` on the `xboxdevwiki-secrets` key and
`roles/cloudsql.client`, and nothing else.

## Notes

- PHP is 7.4.33, the newest that runs MediaWiki 1.28. Neither is supported
  upstream any more.
- Cloud Run must use the gen2 environment: Fil-C programs crash under gVisor.
- `nix/pins.nix` pins filnix and the nixpkgs its `flake.lock` names. Move them
  together, or nothing will be in the binary cache.

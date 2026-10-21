# xboxdevwiki

The MediaWiki behind [xboxdevwiki.net](https://xboxdevwiki.net), packaged with
Nix as a container image for Cloud Run. Every program in the image is compiled
with [Fil-C](https://fil-c.org), a memory-safe implementation of C and C++.

## Commands

No flakes and no channels: inputs are pinned by hash in `nix/pins.nix`.

```sh
nix run -f . deploy                      # build, push, release on Cloud Run
$(nix-build -A image) | docker load      # just build the image, and load it
```

`deploy` uses your `gcloud` credentials, which need to be able to push to
`gcr.io/xqemu-154113` and deploy to Cloud Run. Extra arguments go to
`gcloud run deploy`, e.g. `nix run -f . deploy -- --no-traffic --tag canary`.

Building the Fil-C compiler takes hours, so use filnix's binary cache. Either
add this to `nix.conf` (as a trusted user) or pass each line with `--option`:

```ini
extra-substituters = https://filc.cachix.org
extra-trusted-public-keys = filc.cachix.org-1:8rA7kXyu1HaJuMTsAKfA9fU/+r8YtLv5KiZ5hfDNZMk=
```

With it, the only things compiled locally are lighttpd, ImageMagick and four
small image libraries: about a quarter of an hour on four cores. The image is
1.2 GB, 320 MB compressed; Fil-C binaries are several times the usual size.

### Running it locally

```sh
docker run --rm -p 8080:8080 \
  -e WG_DB_SERVER=host:3306 -e WG_DB_PASSWORD=... -e WG_SECRET_KEY=... \
  -e GCS_ACCESS_KEY=... -e GCS_SECRET_KEY=... \
  gcr.io/xqemu-154113/xboxdevwiki:$(nix-instantiate --eval --raw -A image.imageTag)
```

Without `WG_DB_SERVER`, `LocalSettings.php` connects to the live database.
Any of the other four that is missing is decrypted with Cloud KMS, which only
works on Google Cloud (see [Secrets](#secrets)).

## Layout

| | |
| --- | --- |
| `default.nix` | The attributes above |
| `nix/pins.nix` | nixpkgs and [filnix](https://github.com/mbrock/filnix), by hash |
| `nix/filc.nix` | `pkgsFilc`: nixpkgs cross-compiled with Fil-C |
| `nix/runtime.nix` | The programs in the image, and `php.ini` |
| `nix/lighttpd.nix` | Web server configuration |
| `nix/image.nix`, `nix/rootfs.py` | Assembles the image and checks that it is all Fil-C |
| `nix/entrypoint.php`, `nix/secrets.nix` | Decrypts the secrets when an instance starts |
| `nix/deploy.nix` | `deploy` |
| `mediawiki/htdocs` | MediaWiki 1.28.0 with its extensions and `LocalSettings.php` |

## What is in the image

`entrypoint.php` decrypts the secrets and then becomes lighttpd, the only
long-running command. It serves static files and keeps a pool of `php-cgi`
workers. MediaWiki shells out to ImageMagick (thumbnails),
Pygments on Python 3 (`<syntaxhighlight>`), `diff3` (edit conflicts) and `file`
(upload MIME types), by way of bash and coreutils. It runs as `nobody`, and
nothing but `/tmp` is writable.

Queued jobs (link updates after an edit, mostly) run at the end of whichever
page view finds them, so that visitor waits for one. MediaWiki's way of handing
them to a background request does not work under `php-cgi`; see
`$wgRunJobsAsync` in `LocalSettings.php`. It would not suit Cloud Run either,
which only promises CPU while a request is open.

### All of it is Fil-C

The closure Nix computes for those programs is not all Fil-C. It reaches
ordinary x86-64 packages through things that never run, like the `#!` lines of
glibc's helper scripts, and the toolchain's sysroot has programs of its own.
So `nix/rootfs.py` copies the closure file by file and classifies every ELF
file it meets:

- **Fil-C**: links `libpizlo.so`, as all of the Fil-C compiler's output does,
  its libc and libc++ included. Kept.
- **The Fil-C runtime**: `ld-fil1-x86_64.so`, `libpizlo.so`, `libyolocimpl.so`
  and `libyolomimpl.so`: the loader, the allocator, collector and syscall
  layer, and the libc those use. Fil-C programs stand on this; it cannot itself
  be compiled with Fil-C. Kept, if identical to the toolchain's own copy.
- **Anything else**. Left out.

It then scans the result again from scratch and **fails the build** if it finds
an ELF file of the third kind, a static library, a script whose interpreter is
missing or a dangling symlink, or if one of the programs MediaWiki runs is not
there. What was left out and the final tally are in
`$(nix-build -A image.rootfs)/nix-support/rootfs.log`.

### PHP 7.4

MediaWiki 1.28 cannot run on PHP 8, and no PHP 7 is supported upstream any
more. The image has 7.4.33, the last release of the last line 1.28 runs on.
Memory-safety bugs found in it since then are not fixed, but under Fil-C they
stop the worker with a panic instead of corrupting memory. Bugs that are not
memory errors are as exploitable as ever, in PHP and in MediaWiki 1.28 alike;
the real fix is to upgrade MediaWiki. Its database can only be upgraded in
steps (1.28 → 1.35 → 1.43 → current).

1.28 predates 7.4, and six lines in `mediawiki/htdocs` are changed for it.
Two are regular expressions that PCRE2 (PHP 7.3 and later) refuses to compile,
which broke uploads; the others only silence warnings. Every other regular
expression literal in the tree compiles, and every file that can be loaded
passes `php -l`.

One more change fixes a bug of 1.28.0's own. Two workers racing for the same
queued job could leave one of them retrying forever in
`JobQueueDB::claimRandom()`, until PHP's time limit turned the page view into
an error. Slower workers make that race easier to lose.

`git log -p -- mediawiki/htdocs/includes mediawiki/htdocs/languages
mediawiki/htdocs/extensions` has all of them.

### Pygments

The `pygmentize` bundled with SyntaxHighlight_GeSHi is Pygments 2.1, which
needs Python 2 or a long-gone Python 3, so the image has the current release.
The extension's stylesheet and list of lexers are generated from Pygments; to
regenerate them after a Pygments update, run its `maintenance/updateCSS.php` and
`maintenance/updateLexerList.php` in the image, with this checkout mounted.

### ImageMagick

Built with 8 bits per channel, which is what thumbnails are and takes a quarter
of the memory of the default. Its `policy.xml` allows PNG, JPEG and GIF and
nothing else, whatever a file is called, has no delegates, and gives up beyond
128 MiB of pixels. The largest image MediaWiki will scale (`$wgMaxImageArea`,
12.5 megapixels) peaks at about 200 MiB of memory all told.

### Things Fil-C changes

- PHP runs about 1.5 to 4 times slower and uses more memory. Four workers under
  load use a bit over 500 MiB, hence `--memory 1Gi`; and as there are only
  four, `--concurrency 8`.
- It needs Cloud Run's second-generation execution environment, a real Linux
  kernel. The first generation is gVisor, where bash and Python built with
  Fil-C crash at startup (in `libpizlo.so`; seen with runsc 20260406).
- No JIT, in PHP's PCRE or anywhere else: Fil-C cannot run generated code.
- Memory holding pointers cannot be shared between processes, so each PHP
  worker has its own opcode cache.
- `$wgMaxShellMemory` is 0. MediaWiki enforces it with `ulimit -v`, and Fil-C
  programs reserve much more address space than they use. ImageMagick's own
  limit takes its place.

## Secrets

`LocalSettings.php` reads four environment variables. Their values are in
`nix/secrets.nix`, encrypted with Cloud KMS, and that is all the image has.
When an instance starts, `nix/entrypoint.php` gets a token for the service's
own service account from the metadata server, has Cloud KMS decrypt them, and
passes them to lighttpd in its environment. The plaintext is never in the
image, the Nix store, the service's configuration or on the deployer's machine.

Passing errors are retried. If it still fails the container exits, saying why.
For a new revision that means Cloud Run keeps serving the previous one.

The service account needs permission to decrypt. Once:

```sh
gcloud kms keys add-iam-policy-binding xboxdevwiki-secrets \
  --project xqemu-154113 --location global --keyring xboxdevwiki-keyring \
  --role roles/cloudkms.cryptoKeyDecrypter \
  --member "serviceAccount:$(gcloud run services describe xboxdevwiki \
    --project xqemu-154113 --region us-central1 \
    --format 'value(spec.template.spec.serviceAccountName)')"
```

## Updating

`nix/pins.nix` has the filnix revision and the nixpkgs revision its
`flake.lock` names; move them together, or nothing will be in the binary cache.

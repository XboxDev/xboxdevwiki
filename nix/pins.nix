# Pinned inputs. No flakes, no channels: everything is fetched by hash.
let
  github =
    {
      owner,
      repo,
      rev,
      sha256,
    }:
    builtins.fetchTarball {
      url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
      inherit sha256;
    };
in
{
  # Fil-C packaged as a nixpkgs cross toolchain, plus the per-package ports.
  filnix = github {
    owner = "mbrock";
    repo = "filnix";
    rev = "991ff5c271d4e6c6869ad60e18504e1f0da4d4d9";
    sha256 = "1hb0h4q2wkf0lw46jz6j7zi6cfsfv32cr0w2lyq3lka8i44z25pd";
  };

  # The nixpkgs revision filnix is developed (and its binary cache built)
  # against: nixpkgs plus the gnufilc0 ABI. Keep in sync with filnix/flake.lock.
  nixpkgs = github {
    owner = "lessrest";
    repo = "filnixpkgs";
    rev = "e63c68034d742160a48ca80640442337e6356cf4";
    sha256 = "16qqvxs688db51aaprjhvz0q891na4342fww2skgmx1qkfsf1fc5";
  };
}

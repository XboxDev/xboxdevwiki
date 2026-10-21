# nix-build -A image        a script that writes the image to stdout
# nix run -f . deploy       build, push and release it on Cloud Run
#
# See README.md.
let
  inherit (import ./nix/filc.nix { }) pkgs pkgsFilc;

  project = "xqemu-154113";
  runtime = import ./nix/runtime.nix { inherit pkgsFilc; };
in
rec {
  inherit runtime;

  image = import ./nix/image.nix {
    inherit pkgs runtime;
    name = "gcr.io/${project}/xboxdevwiki";
  };

  deploy = import ./nix/deploy.nix { inherit pkgs image project; };
}

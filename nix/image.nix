# The container image: MediaWiki, and Fil-C builds of everything that runs it.
{
  pkgs,
  runtime,
  name,
}:
let
  inherit (pkgs) lib;

  mediawiki = builtins.path {
    name = "mediawiki";
    path = ../mediawiki/htdocs;
  };

  lighttpdConf = pkgs.callPackage ./lighttpd.nix {
    inherit (runtime) php;
    documentRoot = mediawiki;
  };

  # /bin, for entrypoint.sh, LocalSettings.php, wfShellExec() and anyone who
  # execs into the container. /usr/bin is the same directory.
  bin = pkgs.buildEnv {
    name = "bin";
    paths = with runtime; [
      bash
      coreutils
      curl
      diffutils
      file
      imagemagick
      jq
      php
      pygmentize
    ];
    pathsToLink = [ "/bin" ];
  };

  secrets = pkgs.writeText "secrets.json" (
    builtins.toJSON { inherit (import ./secrets.nix) key ciphertexts; }
  );

  command = [
    "${runtime.bash}/bin/bash"
    "${./entrypoint.sh}"
    "${secrets}"
    runtime.caBundle
    "${runtime.lighttpd}/bin/lighttpd"
    "-D"
    "-f"
    "${lighttpdConf}"
  ];

  # The cached PHP comes with every SAPI, at 50 MB each, and its extensions
  # refer to the headers they were built against.
  unwanted = [
    "${runtime.php.unwrapped.dev}"
  ]
  ++
    lib.concatMap
      (program: [
        "${runtime.php}/bin/${program}"
        "${runtime.php.unwrapped}/bin/${program}"
      ])
      [
        "php-fpm"
        "phpdbg"
      ];

  # What is run by name: see entrypoint.sh, LocalSettings.php, wfShellExec()
  # and includes/limit.sh.
  required = lib.filter (lib.hasPrefix "/") command ++ [
    "/bin/base64"
    "/bin/bash"
    "/bin/curl"
    "/bin/jq"
    "/bin/sh"
    "/bin/pygmentize"
    "/usr/bin/diff3"
    "/usr/bin/file"
    "/usr/bin/magick"
    "/usr/bin/timeout"
  ];

  rootfs =
    pkgs.runCommand "xboxdevwiki-rootfs"
      {
        nativeBuildInputs = [
          pkgs.patchelf
          pkgs.python3
        ];
        closure = pkgs.closureInfo {
          rootPaths = [ bin ] ++ lib.filter (lib.hasPrefix builtins.storeDir) command;
        };
      }
      ''
        mkdir -p $out/etc $out/usr
        ln -s ${bin}/bin $out/bin
        ln -s ${bin}/bin $out/usr/bin
        python3 ${./rootfs.py} --closure $closure/store-paths --out $out \
          --runtime ${runtime.libc}/lib \
          --unwanted ${toString unwanted} \
          --required ${toString required} \
          | tee rootfs.log
        echo 'nobody:x:65534:65534:nobody:/nonexistent:/bin/false' > $out/etc/passwd
        echo 'nobody:x:65534:' > $out/etc/group
        echo 'hosts: files dns' > $out/etc/nsswitch.conf
        mkdir -p $out/nix-support
        mv rootfs.log $out/nix-support/
      '';
in
pkgs.dockerTools.streamLayeredImage {
  inherit name;
  # rootfs has its own, filtered /nix/store; don't add the unfiltered closure.
  includeStorePaths = false;
  extraCommands = ''
    cp -a ${rootfs}/{bin,etc,nix,usr} .
    mkdir -m 1777 tmp
  '';
  config = {
    Cmd = command;
    User = "65534:65534";
    Env = [ "PATH=/bin" ];
    ExposedPorts."8080/tcp" = { };
  };
  passthru = { inherit rootfs mediawiki lighttpdConf; };
}

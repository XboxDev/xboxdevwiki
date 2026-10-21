# The programs that go into the image. Everything here comes from pkgsFilc.
{ pkgsFilc }:
let
  inherit (pkgsFilc) lib;
in
rec {
  caBundle = "${pkgsFilc.cacert}/etc/ssl/certs/ca-bundle.crt";

  # MediaWiki 1.28 predates PHP 8 (it needs each(), create_function(), ...), so
  # this is the last release of the newest PHP line it runs on. 7.4 has been
  # out of support since 2022; Fil-C is what stands between its unfixed memory
  # bugs and an exploit.
  php = pkgsFilc.php74.buildEnv {
    extensions =
      # By name: in this `rec`, a bare `curl` would be the program below.
      { all, ... }:
      map (name: all.${name}) [
        "ctype"
        "curl" # AWS SDK
        "dom"
        "fileinfo"
        "filter"
        "iconv"
        "intl"
        "json"
        "mbstring"
        "mysqli"
        "mysqlnd"
        "opcache"
        "openssl"
        "posix"
        "session"
        "simplexml" # AWS SDK
        "tokenizer"
        "xmlreader"
        "xmlwriter" # AWS SDK
        "zlib"
      ];
    extraConfig = ''
      ; MediaWiki 1.28 is full of constructs 7.x deprecates.
      error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT & ~E_NOTICE
      display_errors = Off
      log_errors = On
      expose_php = Off

      curl.cainfo = ${caBundle}
      openssl.cafile = ${caBundle}

      ; The code lives in the read-only Nix store and never changes.
      opcache.enable = 1
      opcache.validate_timestamps = 0
      opcache.memory_consumption = 64
      opcache.max_accelerated_files = 8000
    '';
  };

  # The pygmentize bundled with SyntaxHighlight_GeSHi REL1_28 is Pygments 2.1,
  # which needs Python 2 or an old Python 3. Pygments is pure Python, so run
  # the current release's source on the Fil-C interpreter.
  pygmentize = pkgsFilc.stdenv.mkDerivation {
    pname = "pygmentize";
    inherit (pkgsFilc.python3Packages.pygments) version src;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/lib $out/bin
      cp -r pygments $out/lib/
      # Fil-C programs run on the build machine; the store is read-only later.
      ${pkgsFilc.python3}/bin/python3 -m compileall -q $out/lib
      cat > $out/bin/pygmentize <<END
      #!${pkgsFilc.python3}/bin/python3 -I
      import sys
      sys.path.insert(0, "$out/lib")
      from pygments.cmdline import main
      sys.exit(main(sys.argv))
      END
      chmod +x $out/bin/pygmentize
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      echo 'int main(void) { return 0; }' | $out/bin/pygmentize -l c -f html | grep -q '<span class="kt">int</span>'
    '';
  };

  # Thumbnailing only ever sees $wgFileExtensions (png, gif, jpg, jpeg), so
  # leave out X11, fonts and the exotic codecs.
  imagemagick =
    (pkgsFilc.imagemagick.override {
      libX11Support = false;
      libXtSupport = false;
      fontconfigSupport = false;
      freetypeSupport = false;
      libraqmSupport = false;
      djvulibreSupport = false;
      openexrSupport = false;
      librawSupport = false;
      liblqr1Support = false;
      libultrahdrSupport = false;
      openjpegSupport = false;
      libxml2Support = false;
      fftwSupport = false;
    }).overrideAttrs
      (old: {
        # Thumbnails are 8 bits per channel. Nixpkgs' default of 16-bit floats
        # takes four times the memory: 16 bytes per pixel, several times over.
        configureFlags = old.configureFlags ++ [
          "--with-quantum-depth=8"
          "--disable-hdri"
        ];

        # ImageMagick goes by a file's content, not its name, so hold it to the
        # formats above. Delegates hand files to other programs (Ghostscript,
        # LibreOffice, ...), none of which are in the image.
        #
        # The resource limits stand in for $wgMaxShellMemory. Beyond `memory`
        # the pixels would go to files in /tmp, which on Cloud Run is memory
        # too, so fail instead. $wgMaxImageArea (12.5 Mpx) takes between 64 and 96 MiB.
        postInstall = builtins.replaceStrings [ "Q16HDRI" ] [ "Q8" ] old.postInstall + ''
          echo '<delegatemap/>' > $out/etc/ImageMagick-7/delegates.xml
          cat > $out/etc/ImageMagick-7/policy.xml <<END
          <policymap>
            <policy domain="delegate" rights="none" pattern="*"/>
            <policy domain="filter" rights="none" pattern="*"/>
            <policy domain="path" rights="none" pattern="@*"/>
            <policy domain="coder" rights="none" pattern="*"/>
            <policy domain="coder" rights="read | write" pattern="{PNG,JPEG,JPG,GIF}"/>
            <policy domain="resource" name="memory" value="128MiB"/>
            <policy domain="resource" name="map" value="0B"/>
            <policy domain="resource" name="disk" value="0B"/>
            <policy domain="resource" name="thread" value="1"/>
            <policy domain="resource" name="time" value="120"/>
          </policymap>
          END
        '';
      });

  # filnix turns these on, and links mod_magnet against the build machine's Lua.
  lighttpd = pkgsFilc.lighttpd.override {
    enableMagnet = false;
    enableWebDAV = false;
    enablePam = false;
  };

  # The toolchain's sysroot: Fil-C's libc and libc++, and the Fil-C runtime.
  inherit (pkgsFilc.stdenv.cc) libc;

  inherit (pkgsFilc)
    bash # wfShellExec(): /bin/sh -c, and /bin/bash includes/limit.sh
    coreutils # limit.sh: timeout
    curl # entrypoint.sh
    diffutils # $wgDiff3
    file # $wgMimeDetectorCommand
    jq # entrypoint.sh
    ;
}

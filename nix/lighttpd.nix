# lighttpd serves static files and runs php-cgi itself, so it is the image's
# only long-running command. Replaces apache2/ and mediawiki/conf/.
{
  writeText,
  php,
  documentRoot,
  port ? 8080,
  # PHP workers. Fil-C cannot share memory that holds pointers between
  # processes, so each worker has an opcode cache of its own.
  workers ? 4,
}:
let
  entryPoints = "/(?:index|api|load|thumb|thumb_handler|img_auth|opensearch_desc)\\.php";
in
writeText "lighttpd.conf" ''
  server.port = ${toString port}
  server.document-root = "${documentRoot}"
  server.upload-dirs = ( "/tmp" )
  server.tag = ""
  server.modules = ( "mod_rewrite", "mod_fastcgi" )

  # $wgArticlePath is "/$1", so page titles share the URL space with the files
  # of the document root. Only MediaWiki's entry points and static assets are
  # served from disk; every other URL is a page title. MediaWiki reads it from
  # REQUEST_URI, which a rewrite leaves alone. This also keeps includes/,
  # maintenance/, mw-config/, ... private, which took .htaccess files before.
  #
  # An asset's path must not go through a .php file: /extensions/x.php/y.css
  # is x.php with PATH_INFO /y.css.
  url.rewrite-once = (
    "^${entryPoints}(?:[/?]|$)" => "",
    "^/(?:resources|skins|extensions)/(?:(?!\.php)[^?])*\.(?:css|js|png|gif|jpe?g|svg|ico|cur|woff2?|ttf|eot)(?:\?|$)" => "",
    "" => "/index.php''${qsa}",
  )

  # Nothing but the entry points is ever run, whatever the rules above let by.
  static-file.exclude-extensions = ( ".php" )
  $HTTP["url"] =~ "^${entryPoints}(?:/|$)" {
    fastcgi.server = ( ".php" => ( (
      "bin-path" => "${php}/bin/php-cgi",
      "socket" => "/tmp/php-cgi.sock",
      "max-procs" => 1,
      "bin-environment" => (
        "PHP_FCGI_CHILDREN" => "${toString workers}",
        "PHP_FCGI_MAX_REQUESTS" => "1000",
      ),
    ) ) )
  }

  mimetype.assign = (
    ".css" => "text/css; charset=utf-8",
    ".js" => "text/javascript; charset=utf-8",
    ".png" => "image/png",
    ".gif" => "image/gif",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".svg" => "image/svg+xml",
    ".ico" => "image/x-icon",
    ".cur" => "image/x-icon",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2",
    ".ttf" => "font/ttf",
    ".eot" => "application/vnd.ms-fontobject",
  )
''

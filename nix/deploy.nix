# `nix run -f . deploy`: push the image and release it on Cloud Run.
# Replaces cloudbuild.yaml. Uses the caller's gcloud credentials.
{
  pkgs,
  image,
  project,
  region ? "us-central1",
  service ? "xboxdevwiki",
}:
let
  inherit (pkgs) lib;

  # The tag is a hash of the image's contents, so a revision can never drift
  # from what was built and re-running a deploy is idempotent.
  ref = "${image.imageName}:${image.imageTag}";
in
pkgs.writeShellApplication {
  name = "deploy";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.google-cloud-sdk
    pkgs.skopeo
  ];
  text = ''
    umask 077
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    echo "pushing ${ref}" >&2
    export REGISTRY_AUTH_FILE=$tmp/auth.json
    gcloud auth print-access-token \
      | skopeo login --username oauth2accesstoken --password-stdin ${lib.head (lib.splitString "/" image.imageName)}
    ${image} | skopeo copy --insecure-policy docker-archive:/dev/stdin docker://${ref}

    # gen2 is a real Linux kernel. gen1 is gVisor, under which bash and Python
    # built with Fil-C crash at startup. Four PHP workers under load use a bit
    # over 500 MiB, and compile all of MediaWiki when an instance starts. With
    # only four, requests beyond a few should go to another instance.
    #
    # Its own service account, which can reach the database and decrypt the
    # secrets and nothing else: anything in the container can get its token.
    # Ingress is not set here, so a deploy leaves it as it is.
    gcloud run deploy ${service} \
      --project ${project} \
      --region ${region} \
      --image ${ref} \
      --service-account ${service}@${project}.iam.gserviceaccount.com \
      --set-cloudsql-instances ${project}:${region}:xboxdevwiki-db2 \
      --max-instances 60 \
      --concurrency 7 \
      --timeout 900 \
      --memory 1Gi \
      --execution-environment gen2 \
      --cpu-boost \
      --allow-unauthenticated \
      "$@"
  '';
}

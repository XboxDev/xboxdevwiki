# Decrypt the secrets LocalSettings.php reads from the environment, then become
# the web server. Variables that are already set are left alone.
#
# usage: bash entrypoint.sh SECRETS_JSON CA_BUNDLE COMMAND [ARGUMENT...]

set -euo pipefail
export HOME=/nonexistent # curl and jq read dotfiles; keep them out of /tmp

secrets=$1 ca_bundle=$2
shift 2

fetch() {
	curl --silent --show-error --fail --retry 3 --retry-max-time 10 --cacert "$ca_bundle" "$@"
}

key=$(jq -re .key "$secrets")
names=$(jq -re '.ciphertexts | keys[]' "$secrets")
token=

for name in $names; do
	[[ -v $name ]] && continue
	[[ -n $token ]] || token=$(fetch --header 'Metadata-Flavor: Google' \
		http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token |
		jq -re .access_token)
	# The token goes by file descriptor: anyone can read a command line.
	value=$(jq ".ciphertexts | { ciphertext: .$name }" "$secrets" |
		fetch --header @<(echo "Authorization: Bearer $token") --json @- \
			"https://cloudkms.googleapis.com/v1/$key:decrypt" |
		jq -re .plaintext | base64 --decode)
	export "$name=$value"
done

exec "$@"

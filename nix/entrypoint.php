<?php
// The image's entry point: decrypt the secrets LocalSettings.php reads from the
// environment, then become the web server.
//
// usage: php entrypoint.php SECRETS_JSON COMMAND [ARGUMENT...]
//
// SECRETS_JSON is nix/secrets.nix. The instance's own service account does the
// decrypting, so it needs roles/cloudkms.cryptoKeyDecrypter on the key.
// Variables that are already set are left alone, so that the image runs
// outside Google Cloud.

function fail( $message ) {
	fwrite( STDERR, "entrypoint: $message\n" );
	exit( 1 );
}

function request( $curl, $url, array $headers, $body = null ) {
	curl_setopt_array( $curl, [
		CURLOPT_URL => $url,
		CURLOPT_HTTPHEADER => $headers,
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_CONNECTTIMEOUT => 5,
		CURLOPT_TIMEOUT => 20,
	] );
	if ( $body !== null ) {
		curl_setopt( $curl, CURLOPT_POSTFIELDS, json_encode( $body ) );
	}
	// This runs whenever an instance starts, with a visitor waiting for it, so
	// don't give up over a hiccup.
	for ( $attempt = 1; ; $attempt++ ) {
		$response = curl_exec( $curl );
		$status = curl_getinfo( $curl, CURLINFO_RESPONSE_CODE );
		if ( $status === 200 ) {
			return json_decode( $response, true );
		}
		$error = $response === false ? curl_error( $curl ) : "HTTP $status: $response";
		$transient = $response === false || $status === 429 || $status >= 500;
		if ( !$transient || $attempt === 4 ) {
			fail( "$url: $error" );
		}
		fwrite( STDERR, "entrypoint: $url: $error; retrying\n" );
		usleep( 250000 * $attempt );
	}
}

$secrets = json_decode( file_get_contents( $argv[1] ), true );
$command = array_slice( $argv, 2 );

$environment = getenv();
$missing = array_diff_key( $secrets['ciphertexts'], $environment );
if ( $missing ) {
	$token = request(
		curl_init(),
		'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token',
		[ 'Metadata-Flavor: Google' ]
	)['access_token'];

	$kms = curl_init();
	foreach ( $missing as $name => $ciphertext ) {
		$plaintext = request(
			$kms,
			"https://cloudkms.googleapis.com/v1/{$secrets['key']}:decrypt",
			[ "Authorization: Bearer $token", 'Content-Type: application/json' ],
			[ 'ciphertext' => $ciphertext ]
		)['plaintext'];
		$environment[$name] = rtrim( base64_decode( $plaintext ), "\n" );
	}
}

pcntl_exec( $command[0], array_slice( $command, 1 ), $environment );
fail( "cannot run {$command[0]}: " . pcntl_strerror( pcntl_get_last_error() ) );

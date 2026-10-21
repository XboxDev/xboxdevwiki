# The environment variables LocalSettings.php reads, encrypted with Cloud KMS.
# nix/entrypoint.php decrypts them when an instance starts. To add or change one:
#
#   printf %s "$value" | gcloud kms encrypt --project xqemu-154113 \
#     --location global --keyring xboxdevwiki-keyring --key xboxdevwiki-secrets \
#     --plaintext-file - --ciphertext-file - | base64 -w0
{
  key = "projects/xqemu-154113/locations/global/keyRings/xboxdevwiki-keyring/cryptoKeys/xboxdevwiki-secrets";

  ciphertexts = {
    WG_SECRET_KEY = "CiQAku2zHT5YgsUBs/mgkK9LRx9tAHlfgiGfvhQz98Kj/F0QnIISaQA0vuzdc+B49bkM8RCdTxzaoqke93tzB+WVGayhzg5v7S7Gm+U/tcgTmP2HqFbfVNcDrJhr4a12fqEZ5dmnzMGBUPFhsadJSSnwx/OEbK0g1LkorhpNuxzvS7RFKVVoFu37MgjJFUWxvQ==";
    WG_DB_PASSWORD = "CiQAku2zHVaUblU6tLI3bM8/9FlKxVavKREFjOqgR9JPR2Njn5kSMwA0vuzdqDAPAaK37+2GMmwsIaxSK5YOmlm/ql3A0wtDcWoE+vZTL9rxUBOkQql5PWv3og==";
    GCS_ACCESS_KEY = "CiQAku2zHb+JsaCPWKwfuBC+t0VAaXLfEpkU+vnO1rYIkpWE6yQSZgA0vuzdQ3XvRdejwrJikuDQf6+gudB5QlStqvRJh1AG3wUKdu2w8yRYuM+CYhWZeWxUHS5+ZxLBfpiJfQw06Z/V4oyd1kG5efWn3y6zWniNjifym+iU0/VDq462C3n8/pkH3/m7Lw==";
    GCS_SECRET_KEY = "CiQAku2zHfM7ZTUDfxpuFoBl6yv1GRhRYupSAkZlgJYv6HgnPeQSUQA0vuzd8Z7Jnwoz7yBswAmaddtABlDgHtwRYmz2f8MIgAsEqcSi2a+M0vt7AwrDcLpaOTuCl4spA5gHhyjjEkjGaVnnI8tckMNKjGfaknbdDw==";
  };
}

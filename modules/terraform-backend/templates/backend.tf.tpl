terraform {
  backend "s3" {
    bucket = "${bucket_name}"
    key    = "${state_key}"
    region = "${region}"

    # Scaleway Object Storage S3-compatible endpoint
    endpoint = "${endpoint}"

    # Required flags for S3-compatible storage
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    # Use endpoints block for better compatibility
    endpoints = {
      s3 = "${endpoint}"
    }

    # Note: State locking is not supported with Scaleway Object Storage
    # For teams, consider implementing external locking mechanism
  }
}
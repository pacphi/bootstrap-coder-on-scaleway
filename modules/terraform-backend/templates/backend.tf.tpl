terraform {
  backend "s3" {
    bucket = "${bucket_name}"
    key    = "${state_key}"
    region = "${region}"

    # Required flags for S3-compatible storage
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    # Use endpoints block for S3-compatible storage
    endpoints = {
      s3 = "${endpoint}"
    }

    # Note: State locking is not supported with Scaleway Object Storage
    # For teams, consider implementing external locking mechanism
  }
}
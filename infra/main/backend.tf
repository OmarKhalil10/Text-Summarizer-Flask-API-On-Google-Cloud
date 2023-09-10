terraform {
  backend "gcs" {
    bucket = "bucket-tfstate-0f391615a234a392"
    prefix = "terraform/state"
  }
}
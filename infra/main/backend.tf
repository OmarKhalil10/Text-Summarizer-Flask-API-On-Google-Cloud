terraform {
  backend "gcs" {
    bucket = "bucket-tfstate-f708fe1a360136f1"
    prefix = "terraform/state"
  }
}
terraform {
  backend "s3" {
    bucket       = "venky-terraform-state-13-11-unique"
    key          = "serverless-order/dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
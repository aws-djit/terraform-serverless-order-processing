module "order_platform" {
  source = "./modules/order_platform"

  project_name  = var.project_name
  environment   = var.environment
  email_address = var.email_address
  aws_region    = "ap-south-1"
}
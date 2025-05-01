output "subnet_ids" {
  value = module.network.subnet_ids
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "deploy_key_name" {
  value = aws_key_pair.deploy.key_name
}

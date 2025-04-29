# Output public IP of the instance
output "instance_public_ip" {
  value = module.instances.public_ip
}

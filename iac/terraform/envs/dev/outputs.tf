# Output public IP of the instance
output "instance_ipv6" {
  value = module.instances.ipv6
}

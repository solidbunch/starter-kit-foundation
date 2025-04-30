variable "instance_ami" {
  description = "EC2 instance ami"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "public_key_name" {
  description = "Name of the SSH public key"
  type        = string
}

variable "public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
}

variable "instance_initiated_shutdown_behavior" {
  description = "Ensure the instance stops rather than terminates on OS shutdown"
  type        = string
}

variable "disable_api_termination" {
  description = "Enable termination protection"
  type        = bool
}

variable "disable_api_stop" {
  description = "Enables stop protection"
  type        = bool
}

variable "associate_public_ip_address" {
  description = "Associate a public IPv4 address with the instance"
  type        = bool
}

variable "ipv6_address_count" {
  description = "Number of IPv6 addresses to assign to the instance"
  type        = number
}

variable "tags" {
  description = "Tags to assign to the EC2 instance"
  type        = map(string)
}

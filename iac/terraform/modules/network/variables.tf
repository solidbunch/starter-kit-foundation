variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "assign_generated_ipv6" {
  description = "Assign generated IPv6 CIDR block to the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name tag for the VPC"
  type        = string
}

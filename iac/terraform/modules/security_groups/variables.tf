variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "web_ports" {
  description = "List of ports to open for web (HTTP/HTTPS)"
  type        = list(number)
  default     = [80, 443]
}

variable "ssh_ports" {
  description = "List of ports to open for SSH access"
  type        = list(number)
  default     = [22]
}

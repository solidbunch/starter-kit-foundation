output "allow_http_s_id" {
  description = "ID of the HTTP(S) security group"
  value       = aws_security_group.allow_http_s.id
}

output "allow_ssh_id" {
  description = "ID of the SSH security group"
  value       = aws_security_group.allow_ssh.id
}

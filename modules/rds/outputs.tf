output "endpoint" {
  description = "RDS hostname - stored in Secrets Manager"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS port - always 5432 for PostgreSQL"
  value       = aws_db_instance.main.port
}

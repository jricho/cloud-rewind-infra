output "alb_dns_name" {
  description = "Public DNS of the Application Load Balancer"
  value       = aws_lb.app_lb.dns_name
}

output "rds_endpoint" {
  description = "PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
}

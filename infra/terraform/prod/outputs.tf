output "alb_dns_name" {
  description = "The public DNS of the Load Balancer (Visit this!)"
  value       = aws_lb.app.dns_name
}

output "prod_listener_arn" {
  value = aws_lb_listener.front_end.arn
}

output "prod_ip_blue" {
  value = aws_instance.blue.public_ip
}

output "prod_ip_green" {
  value = aws_instance.green.public_ip
}

output "prod_tg_blue_arn" {
  value = aws_lb_target_group.blue.arn
}

output "prod_tg_green_arn" {
  value = aws_lb_target_group.green.arn
}
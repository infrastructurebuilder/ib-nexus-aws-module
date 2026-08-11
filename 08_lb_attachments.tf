# ==============================================================================
# 8. TARGET GROUP ATTACHMENTS
# ==============================================================================

resource "aws_lb_target_group_attachment" "nexus_core_attachment" {
  target_group_arn = aws_lb_target_group.nexus_core_tg.arn
  target_id        = aws_instance.nexus_server.id
  port             = var.nexus_port
}

resource "aws_lb_target_group_attachment" "docker" {
  for_each = local.docker_ports

  target_group_arn = aws_lb_target_group.docker[each.key].arn
  target_id        = aws_instance.nexus_server.id
  port             = tonumber(each.value)
}
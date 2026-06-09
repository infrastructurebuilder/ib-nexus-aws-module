# ==============================================================================
# 8. TARGET GROUP ATTACHMENTS
# ==============================================================================

resource "aws_lb_target_group_attachment" "nexus_core_attachment" {
  target_group_arn = aws_lb_target_group.nexus_core_tg.arn
  target_id        = aws_instance.nexus_server.id
  port             = 8081
}

resource "aws_lb_target_group_attachment" "nexus_docker_attachment" {
  target_group_arn = aws_lb_target_group.nexus_docker_tg.arn
  target_id        = aws_instance.nexus_server.id
  port             = 8082
}
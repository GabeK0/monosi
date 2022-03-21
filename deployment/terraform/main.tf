data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# --- EC2: Security Group Rules

resource "aws_security_group" "sg" {
  name   = "${var.prefix}-monosi-sg"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "ingress_tcp_22" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ssh_ip_allowlist
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "ingress_tcp_80" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.ssh_ip_allowlist
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "ingress_tcp_3000" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = var.ssh_ip_allowlist
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "egress_tcp_80" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "egress_tcp_443" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

locals {
  user_data = "${file("user_data.sh")}"
}

resource "aws_instance" "monosi" {
  # depends_on           = [aws_security_group.sg]

  ami                  = data.aws_ami.amazon_linux_2.id
  instance_type        = var.instance_type
  count                = 1
  key_name             = var.ssh_key_name

  vpc_security_group_ids = [
    aws_security_group.sg.id
  ]
  subnet_id = var.subnet_id

  user_data            = "${file("user_data.sh")}"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "30"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.prefix}-monosi"
  }
}

resource "aws_elb" "ab_elb" {
  name               = "${var.prefix}-monosi-elb"

  listener {
    instance_port     = 3000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 60
    target              = "HTTP:3000/"
    interval            = 300
  }

  instances                   = [aws_instance.monosi[0].id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  subnets = [var.subnet_id]

  tags = {
    Name = "${var.prefix}-monosi-elb"
  }
}


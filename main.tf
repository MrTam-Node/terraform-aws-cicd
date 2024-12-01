provider "aws" {
  region = "eu-west-3"
}

# Define locals for environment-specific values
locals {
  environment = var.environment
  vpc_name    = "${var.environment}-vpc"
  subnet_name = "${var.environment}-subnet"
  sg_name     = "${var.environment}-sg"
  instance_name = "web-${var.environment}"
}

# Create VPC
resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = local.vpc_name
  }
}

# Create Subnet
resource "aws_subnet" "app_subnet" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = local.subnet_name
  }
}

# Security Group
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.app_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.sg_name
  }
}

# Elastic IP for each instance (For both Test and Production)
resource "aws_eip" "app_eip" {
  count = var.instance_count

  instance = aws_instance.app_instances[count.index].id
  depends_on = [aws_instance.app_instances]
}

# Create EC2 Instances (Test and Production)
resource "aws_instance" "app_instances" {
  count                       = var.instance_count
  ami                         = var.ami_id
  instance_type               = var.environment == "production" ? "t3.2xlarge" : "t3.medium"  # Instance type based on environment
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.app_subnet.id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  tags = {
    Name        = "${local.instance_name}-${count.index + 1}"
    Environment = local.environment
  }
}

# Auto Scaling Group (Only for Production)
resource "aws_launch_configuration" "prod_launch_config" {
  count                  = var.environment == "production" ? 1 : 0
  name                   = "prod-launch-config"
  image_id               = var.ami_id
  instance_type          = "t3.2xlarge"  # For production (6 vCPUs, 8 GB RAM)
  security_groups        = [aws_security_group.app_sg.id]
  key_name               = var.key_name
  associate_public_ip_address = true
}

resource "aws_autoscaling_group" "prod_asg" {
  count                  = var.environment == "production" ? 1 : 0
  desired_capacity       = var.instance_count
  max_size               = 8  # Maximum of 8 instances
  min_size               = 2  # Minimum of 2 instances (you can adjust this)
  vpc_zone_identifier    = [aws_subnet.app_subnet.id]
  launch_configuration   = aws_launch_configuration.prod_launch_config.id

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }

  # Enable auto-scaling based on compute utilization
  health_check_type          = "EC2"
  health_check_grace_period = 300
  force_delete               = true
  wait_for_capacity_timeout   = "0"
}

# CloudWatch Alarm for scaling based on CPU Utilization
resource "aws_cloudwatch_metric_alarm" "cpu_high_alarm" {
  count               = var.environment == "production" ? 1 : 0
  alarm_name          = "high-cpu-utilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"  # Scale up if CPU usage exceeds 80%

  alarm_actions       = [aws_autoscaling_policy.scale_up_policy.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.prod_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low_alarm" {
  count               = var.environment == "production" ? 1 : 0
  alarm_name          = "low-cpu-utilization"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "30"  # Scale down if CPU usage goes below 30%

  alarm_actions       = [aws_autoscaling_policy.scale_down_policy.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.prod_asg.name
  }
}

# Auto Scaling Policy to scale the instances
resource "aws_autoscaling_policy" "scale_up_policy" {
  count               = var.environment == "production" ? 1 : 0
  name                = "scale-up-policy"
  scaling_adjustment  = 1  # Add 1 instance when scaling up
  adjustment_type     = "ChangeInCapacity"
  cooldown            = 300
  autoscaling_group_name = aws_autoscaling_group.prod_asg.name
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  count               = var.environment == "production" ? 1 : 0
  name                = "scale-down-policy"
  scaling_adjustment  = -1  # Remove 1 instance when scaling down
  adjustment_type     = "ChangeInCapacity"
  cooldown            = 300
  autoscaling_group_name = aws_autoscaling_group.prod_asg.name
}

variable "db_username" {
  description = "Database administrator username"
  type        = string
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region"
  default     = "ap-southeast-2"
}

variable "existing_vpc_id" {
  description = "The ID of the existing VPC"
  type        = string
}

variable "public_subnet_a_id" {
  description = "The ID of the existing public subnet A"
  type        = string
}

variable "private_subnet_a_id" {
  description = "The ID of the existing private subnet A"
  type        = string
}

variable "private_subnet_b_id" {
  description = "The ID of the existing private subnet B"
  type        = string
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "main" {
  id = var.existing_vpc_id
}

data "aws_subnet" "public_a" {
  id = var.public_subnet_a_id
}

data "aws_subnet" "private_a" {
  id = var.private_subnet_a_id
}

data "aws_subnet" "private_b" {
  id = var.private_subnet_b_id
}

# --- Security groups ---
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP from the world"
  vpc_id      = data.aws_vpc.main.id

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
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow HTTP from ALB (open for dev)"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to public; restrict for production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow Postgres access from VPC"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EC2 instance (in AZ A only) ---
resource "aws_instance" "web" {
  ami               = "ami-093dc6859d9315726"
  instance_type     = "t2.micro"
  subnet_id         = data.aws_subnet.public_a.id
  security_groups   = [aws_security_group.ec2_sg.id]
  user_data         = file("user_data.sh")

  tags = {
    Name = "nginx-web"
  }
}

# --- ALB (with subnets in two AZs) ---
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [data.aws_subnet.public_a.id]
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.main.id
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "web_instance" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# --- RDS PostgreSQL (uses subnet group with 2 AZs) ---
resource "aws_db_subnet_group" "main" {
  name       = "main-subnet-group"
  subnet_ids = [data.aws_subnet.private_a.id, data.aws_subnet.private_b.id]
}

resource "aws_db_instance" "postgres" {
  identifier              = "app-db"
  allocated_storage       = 20
  engine                  = "postgres"
  engine_version          = "16.3"
  instance_class          = "db.t3.micro"
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  skip_final_snapshot     = true
  publicly_accessible     = false
}
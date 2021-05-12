#############################################################################
# КАКОЙ ИСПОЛЬЗУЕТСЯ ПРОВАЙДЕР И РЕГИОН
#############################################################################

provider "aws" {
  region = "eu-west-2"
}


#############################################################################
# ПАРАМЕТРЫ БЕЗОПАСНОСТИ
############################################################################

# Чтобы ресурс ASG работал, к нему надо приаттачить VPC-подсеть.
# subnet_ids указывает, в какие VPC-подсети должны быть развернуты иснтансы EC2. 
# Синтаксис data.<PROVIDER>_<TYPE>.<NAME>.<ATTRIBUTE>

# Получить ID VPC-подсетей из источника данных aws_vpc.
data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}

# Найти в VPC-подсетях Default VPC.
data "aws_vpc" "default" {
default = true
}


# По умолчанию все AWS-ресурсы, включая ALB, запрещают любой входящий/исходящий трафик. 
# Поэтому настроим группу безопасности, которая разрешит входящий трафик на 80 порт ресурса ALB и исходящий на любой порт этого же ресурса.

resource "aws_security_group" "alb" {
    name = "terraform-alb-security-group"

    # Разрешить входящие HTTP
    ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
    
    ingress {
    from_port = 3389
    to_port = 3389
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
    from_port = 5985
    to_port = 5985
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

    # Разрешить все исходящие
    egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }
}

# Эта группа безопасности применяется к ресурсу aws_launch_configuration
resource "aws_security_group" "instance" {
  name = "terraform-instance-security-group"

  ingress {
    from_port        = 8080
    to_port            = 8080
    protocol        = "tcp"
    cidr_blocks        = ["0.0.0.0/0"]
    }

  ingress {
    from_port        = 3389
    to_port            = 3389
    protocol        = "tcp"
    cidr_blocks        = ["0.0.0.0/0"]
    }
    ingress {
    from_port = 5985
    to_port = 5985
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }
}

#############################################################################
# ALB (Application Load Balancer)
#############################################################################


# alb — имя ресурса.
# name — имя балансировщика.
# load_balancer_type — тип балансировщика.
# subnets — имя VPC-подсети. В этом случае подсеть указана как default. 
# К сведению. По умолчанию при регистрации в AWS для всех регионов автоматически 
# создаются подсети с именем default.
# security_groups — имя группы безопасности, которую создали выше.

resource "aws_lb" "alb" {
    name = "terraform-alb"
    load_balancer_type = "application"
    subnets = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.alb.id]
}

# Создание listener
# http — имя ресурса прослушивателя.
# load_balancer_arn — имя ресурса вышесозданного ALB. В нашем случае имя alb.

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.alb.arn
    port = 80
    protocol = "HTTP"

# Страница 404 если будут запросы, которые не соответствуют никаким правилам прослушивателя.
    default_action {
        type = "fixed-response"
        fixed_response {
        content_type = "text/plain"
        message_body = "404: страница не найдена"
        status_code = 404
        }
    }
}

# Включаем правило прослушивателя, которое отправляет запросы,
# соответствующие любому пути, в целевую группу для ASG.
resource "aws_lb_listener_rule" "asg-listener_rule" {
    listener_arn    = aws_lb_listener.http.arn
    priority        = 100
    
    condition {
        path_pattern {
      values = ["/static/*"]
        #field   = "path-pattern"
        #values  = ["*"]
    }
}    
    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg-target-group.arn
    }
}

# Создаём целевую группу aws_lb_target_group для ASG.
# Каждые 15 сек. будут отправляться HTTP запросы и если ответ 200, то все ОК, иначе
# произойдет переключение на доступный инстанс. 
resource "aws_lb_target_group" "asg-target-group" {
    name = "terraform-aws-lb-target-group"
    port = 8080
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    health_check {
        path                = "/"
        protocol            = "HTTP"
        matcher             = "200"
        interval            = 15
        timeout             = 3
        healthy_threshold   = 2
        unhealthy_threshold = 2
    }
}


#############################################################################
# ИНСТАНСЫ
#############################################################################

# FILEOVER ВЕБ-СЕРВЕР НА UBUNTU 
resource "aws_autoscaling_group" "windows-ec2" {
    launch_configuration = aws_launch_configuration.windows-ec2.name
    vpc_zone_identifier = data.aws_subnet_ids.default.ids
    
    # Включаем интеграцию между ASG и ALB, указав аргумент target_group_arns 
    # на целевую группу aws_lb_target_group.asg-target_group.arn,
    # чтобы целевая группа знала, в какие инстансы EC2 отправлять запросы.   
    target_group_arns = [aws_lb_target_group.asg-target-group.arn]
    health_check_type = "EC2"
        
    desired_capacity   = 2
    min_size = 2
    max_size = 2
    
    tag {
    key = "Name"
    value = "terraform-asg-windows-ec2"
    propagate_at_launch = false
    }
}

resource "aws_launch_configuration" "windows-ec2" {
    image_id = "ami-0ae15c1544cd06ac8"
    instance_type = "t2.micro"
    
    key_name   = "Sverlovych"
    security_groups = [aws_security_group.instance.id]

    # Требуется при использовании launch configuration совместно с auto scaling group.
    # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
    #lifecycle {
    #    create_before_destroy = false
    #}
}


#############################################################################
# DNS ALB
############################################################################

output "alb_dns_name" {
    value = aws_lb.alb.dns_name
    description = "Доменное имя ALB"
}





   # terraform {
   #required_providers {
   # aws = {
   #   source  = "hashicorp/aws"
   #   version = "~> 3.27"
   # }
   #}

   #required_version = ">= 0.14.9"
   #}

   #provider "aws" {
   #profile = "default"
   #region  = "eu-west-2"
   #}

   #resource "aws_instance" "windows_server" {
   #ami           ="ami-0ae15c1544cd06ac8"
   #instance_type = "t2.micro"
   #tags = {
   # Name = "ExampleWindowsServerInstance"
   #}
   #}

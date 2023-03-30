#RDS database using mysql

#RDS database vpc
resource "aws_vpc" "db" {
  cidr_block = "10.0.0.0/16"
  # needed for the interface endpoint
  enable_dns_support   = true
  enable_dns_hostnames = true
}

#internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.db.id

  tags = {
    Name = "main"
  }
}

#route table
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.db.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

# query the AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# creating 2 subnets
resource "aws_subnet" "db1" {
  vpc_id            = aws_vpc.db.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "db-sub1"
  }
}
resource "aws_subnet" "db2" {
  vpc_id            = aws_vpc.db.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "db-sub2"
  }
}

#route table association
resource "aws_route_table_association" "public-rt-association1" {
  subnet_id      = aws_subnet.db1.id
  route_table_id = aws_route_table.public-rt.id
}
resource "aws_route_table_association" "public-rt-association2" {
  subnet_id      = aws_subnet.db2.id
  route_table_id = aws_route_table.public-rt.id
}

# allow data flow between the components
resource "aws_security_group" "db" {
  vpc_id = aws_vpc.db.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 3066
    to_port   = 3066
    protocol  = "tcp"

    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.db.cidr_block]
  }
}

#subnet group ids
resource "aws_db_subnet_group" "db" {
  subnet_ids = [aws_subnet.db1.id, aws_subnet.db2.id]
}

#password generator
resource "random_password" "password" {
  length  = 16
  special = false
}

#database instance
resource "aws_db_instance" "default" {
  username = "admin"
  password = random_password.password.result

  allocated_storage   = 20
  storage_type        = "gp2"
  db_name             = "quoredb"
  engine              = "mysql"
  engine_version      = "8.0.32"
  instance_class      = "db.t2.micro"
  skip_final_snapshot = true
  publicly_accessible = false #Change it to true for public accessibilty
  # attach the security group
  vpc_security_group_ids = [aws_security_group.db.id]
  # deploy to the subnets
  db_subnet_group_name = aws_db_subnet_group.db.name

  tags = {
    Name = "quoredb"
  }
}

#credential tag
resource "aws_secretsmanager_secret" "rds_credentials" {
  name = "credentials"
}

#secret manager
resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id     = aws_secretsmanager_secret.rds_credentials.id
  secret_string = <<EOF
{
  "username": "${aws_db_instance.default.username}",
  "password": "${random_password.password.result}",
  "engine": "mysql",
  "host": "${aws_db_instance.default.endpoint}",
  "port": ${aws_db_instance.default.port},
}
EOF
}
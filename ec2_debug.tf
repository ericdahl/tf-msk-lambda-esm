resource "aws_iam_role" "ec2_debug" {
  name = "ec2-debug"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_debug_ssm" {
  role       = aws_iam_role.ec2_debug.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_debug" {
  name = "ssm_instance_profile"
  role = aws_iam_role.ec2_debug.name
}

data "aws_iam_policy_document" "ec2_debug" {
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:AlterCluster",
      "kafka-cluster:DescribeCluster"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:*Topic*",
      "kafka-cluster:WriteData",
      "kafka-cluster:ReadData"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterGroup",
      "kafka-cluster:DescribeGroup"
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "kafka" {
  name        = "KafkaPolicy"
  description = "IAM policy for MSK tutorial cluster"
  policy      = data.aws_iam_policy_document.ec2_debug.json
}

resource "aws_iam_role_policy_attachment" "ec2_debug_kafka_cluster" {
  policy_arn = aws_iam_policy.kafka.arn
  role       = aws_iam_role.ec2_debug.name
}


resource "aws_security_group" "ec2_debug" {
  vpc_id = aws_vpc.default.id
}

resource "aws_security_group_rule" "ec2_debug_ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  security_group_id = aws_security_group.ec2_debug.id
}

resource "aws_security_group_rule" "ec2_debug_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # -1 indicates all protocols
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2_debug.id
}


resource "aws_key_pair" "default" {
  public_key = var.public_key
}

resource "aws_instance" "ec2_debug" {
  ami = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_debug.name

  vpc_security_group_ids = [aws_security_group.ec2_debug.id]
  subnet_id              = aws_subnet.public["10.0.0.0/24"].id

  key_name = aws_key_pair.default.key_name

  lifecycle {
    ignore_changes = [ami]
  }

  user_data = <<EOF
#!/bin/bash
sudo yum -y install java-11
wget https://archive.apache.org/dist/kafka/2.8.1/kafka_2.12-2.8.1.tgz
tar -xzf kafka_2.12-2.8.1.tgz
ln -s /kafka_2.12-2.8.1 /kafka
cd /kafka/libs
wget https://github.com/aws/aws-msk-iam-auth/releases/download/v1.1.1/aws-msk-iam-auth-1.1.1-all.jar

echo 'security.protocol=SASL_SSL' >> /kafka_2.12-2.8.1/bin/client.properties
echo 'sasl.mechanism=AWS_MSK_IAM' >> /kafka_2.12-2.8.1/bin/client.properties
echo 'sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;' >> /kafka_2.12-2.8.1/bin/client.properties
echo 'sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler' >> /kafka_2.12-2.8.1/bin/client.properties


EOF
}

output "instance_id" {
  value = aws_instance.ec2_debug.id
}

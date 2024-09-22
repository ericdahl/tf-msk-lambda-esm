provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Name       = "tf-msk-lambda-esm"
      Repository = "https://github.com/ericdahl/tf-msk-lambda-esm"
    }
  }
}

data "aws_default_tags" "default" {}

locals {
  name = data.aws_default_tags.default.tags["Name"]
}

resource "aws_security_group" "msk" {
  vpc_id = aws_vpc.default.id
}

resource "aws_security_group_rule" "msk_ingress_ec2" {
  from_port                = 9098
  protocol                 = "tcp"
  security_group_id        = aws_security_group.msk.id
  to_port                  = 9098
  type                     = "ingress"
  source_security_group_id = aws_security_group.ec2_debug.id
  description              = "allow ingress from ec2_debug"
}

# resource "aws_security_group_rule" "msk_ingress_lambda_producer" {
#   from_port                = 9098
#   protocol                 = "tcp"
#   security_group_id        = aws_security_group.msk.id
#   to_port                  = 9098
#   type                     = "ingress"
#   source_security_group_id = aws_security_group.lambda_producer.id
#   description              = "allow ingress from lambda_producer"
# }
#
resource "aws_security_group_rule" "msk_ingress_lambda_consumer" {
  from_port                = 9098
  protocol                 = "tcp"
  security_group_id        = aws_security_group.msk.id
  to_port                  = 9098
  type                     = "ingress"
  source_security_group_id = aws_security_group.lambda_consumer.id
  description              = "allow ingress from lambda_consumer"
}

# shouldn't be necessary TODO
resource "aws_security_group_rule" "msk_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # -1 indicates all protocols
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.msk.id
}

resource "aws_msk_cluster" "default" {
  cluster_name           = local.name
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 2
  configuration_info {
    arn      = aws_msk_configuration.default.arn
    revision = aws_msk_configuration.default.latest_revision
  }
  broker_node_group_info {
    client_subnets = values(aws_subnet.public)[*].id
    instance_type = "kafka.t3.small"
    security_groups = [aws_security_group.msk.id]

    connectivity_info {
      vpc_connectivity {
        client_authentication {
          sasl {
            iam = true
          }

        }
      }
    }
  }
}

resource "aws_msk_configuration" "default" {
  name           = local.name

  server_properties = <<PROPERTIES
auto.create.topics.enable = true
delete.topic.enable = true
PROPERTIES
}

data "aws_iam_policy_document" "assume_policy_lambda" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
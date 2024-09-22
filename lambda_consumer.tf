resource "aws_iam_role" "lambda_consumer" {
  name               = "lambda-consumer"
  assume_role_policy = data.aws_iam_policy_document.assume_policy_lambda.json
}

data "aws_iam_policy_document" "lambda_consumer" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    actions = [
      "events:PutEvents",
      "kafka:DescribeCluster",
      "kafka:GetBootstrapBrokers",
      "kafka:DescribeTopic",
      "kafka:Write",
      "kafka:Read",
      "kafka:CreateTopic"
    ]

    resources = ["*"]
  }

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

  # TODO: cleanup
  statement {
    effect = "Allow"
    actions = [
      "kafka:*",
      "kafka-cluster:*"
    ]
    resources = ["*"]
  }
}


resource "aws_iam_role_policy" "lambda_consumer" {
  role   = aws_iam_role.lambda_consumer.id
  policy = data.aws_iam_policy_document.lambda_consumer.json
}


resource "aws_iam_role_policy_attachment" "lambda_consumer_vpc_policy" {
  role       = aws_iam_role.lambda_consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "archive_file" "consumer_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/consumer/main.py"
  output_path = "${path.module}/lambda/consumer/lambda_function.zip"
}

resource "aws_lambda_function" "consumer" {
  filename         = data.archive_file.consumer_zip.output_path
  function_name    = "consumer"
  role             = aws_iam_role.lambda_consumer.arn
  handler          = "main.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256(data.archive_file.consumer_zip.output_path)
  timeout          = 60

  vpc_config {
    security_group_ids = [aws_security_group.lambda_consumer.id]
    subnet_ids         = [aws_subnet.public["10.0.0.0/24"].id]
  }
}

resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/consumer"
  retention_in_days = 1
}

resource "aws_lambda_event_source_mapping" "consumer" {
  function_name    = aws_lambda_function.consumer.function_name
  event_source_arn = aws_msk_cluster.default.arn
  topics           = ["DemoTopic"]
  amazon_managed_kafka_event_source_config {
    consumer_group_id = aws_lambda_function.consumer.function_name
  }
  starting_position = "LATEST"

}

resource "aws_security_group" "lambda_consumer" {
  vpc_id = aws_vpc.default.id
}

resource "aws_security_group_rule" "lambda_consumer_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # -1 indicates all protocols
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lambda_consumer.id
}

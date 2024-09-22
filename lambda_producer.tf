resource "aws_iam_role" "lambda_producer" {
  name               = "lambda-producer"
  assume_role_policy = data.aws_iam_policy_document.assume_policy_lambda.json
}

data "aws_iam_policy_document" "lambda_producer" {
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
}


resource "aws_iam_role_policy" "lambda_producer" {
  role   = aws_iam_role.lambda_producer.id
  policy = data.aws_iam_policy_document.lambda_producer.json
}


resource "aws_iam_role_policy_attachment" "lambda_producer_vpc_policy" {
  role       = aws_iam_role.lambda_producer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "null_resource" "build_lambda_producer_package" {
  provisioner "local-exec" {
    command = <<EOT
      cd lambda/producer && \
      docker build -t lambda-builder . && \
      docker run --rm -v $(pwd):/app lambda-builder sh -c 'cp /lambda_function.zip /app/lambda_function.zip'
    EOT
  }

  triggers = {
    always_run = "${sha1(file("${path.module}/lambda/producer/src/main.py"))}"
  }
}


resource "aws_lambda_function" "producer" {
  filename         = "${path.module}/lambda/producer/lambda_function.zip"
  function_name    = "producer"
  role             = aws_iam_role.lambda_producer.arn
  handler          = "main.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = try(filebase64sha256("${path.module}/lambda/producer/lambda_function.zip"), 0)
  environment {
    variables = {
      BS    = aws_msk_cluster.default.bootstrap_brokers_sasl_iam
      TOPIC = "DemoTopic"
    }
  }

  vpc_config {
    security_group_ids = [aws_security_group.lambda_producer.id]
    subnet_ids         = [aws_subnet.public["10.0.0.0/24"].id]

  }

  depends_on = [null_resource.build_lambda_producer_package]
}

resource "aws_cloudwatch_log_group" "producer" {
  name              = "/aws/lambda/producer"
  retention_in_days = 1
}

resource "aws_cloudwatch_event_rule" "lambda_producer" {
  name                = "every_minute_producer"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "lambda_producer" {
  rule      = aws_cloudwatch_event_rule.lambda_producer.name
  target_id = "lambda"
  arn       = aws_lambda_function.producer.arn
}

resource "aws_lambda_permission" "producer_allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_producer.arn
}

resource "aws_security_group" "lambda_producer" {
  vpc_id = aws_vpc.default.id
}

resource "aws_security_group_rule" "lambda_producer_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # -1 indicates all protocols
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lambda_producer.id
}

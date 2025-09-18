# Terraform configuration for AWS Lambda to list all IAM roles

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_iam_list" {
  name        = "lambda_iam_list_policy"
  description = "Allow Lambda to list IAM roles"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "iam:ListRoles"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_iam_list_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_iam_list.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "list_iam_roles" {
  function_name = "list_iam_roles"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "list_iam_roles.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/list_iam_roles.py"
  output_path = "${path.module}/lambda/list_iam_roles.zip"
}

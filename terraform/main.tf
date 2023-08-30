terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-southeast-2"
}


#
# Lambda function
#

resource "aws_iam_role" "signer_lambda" {
  name = "${var.lambda_name}_role"
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

resource "aws_iam_policy" "signer_lambda_logs" {
  name = "${var.lambda_name}_log_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = ["arn:aws:logs:*:*:*"]
    }]
  })
}

// https://docs.aws.amazon.com/healthimaging/latest/devguide/security-iam-awsmanpol.html#security-iam-awsmanpol-AWSHealthImagingReadOnlyAccess
resource "aws_iam_policy" "signer_lambda_health_imaging_read_only" {
  name = "${var.lambda_name}_signer_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
            "medical-imaging:GetDICOMImportJob",
            "medical-imaging:GetDatastore",
            "medical-imaging:GetImageFrame",
            "medical-imaging:GetImageSet",
            "medical-imaging:GetImageSetMetadata",
            "medical-imaging:ListDICOMImportJobs",
            "medical-imaging:ListDatastores",
            "medical-imaging:ListImageSetVersions",
            "medical-imaging:ListTagsForResource",
            "medical-imaging:SearchImageSets"
        ]
      Resource = ["*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "signer_lambda" {
  for_each = {
    policy1 = aws_iam_policy.signer_lambda_logs.arn
    policy2 = aws_iam_policy.signer_lambda_health_imaging_read_only.arn
  }

  policy_arn = each.value
  role       = aws_iam_role.signer_lambda.name
}

resource "aws_lambda_function" "signer_lambda" {
  function_name    = var.lambda_name
  role             = aws_iam_role.signer_lambda.arn
  handler          = "main"
  filename         = "signer.zip"
  source_code_hash = filebase64sha256("signer.zip")
  runtime          = "provided.al2"

  environment {
    variables = {
      AWS_HOST = "runtime-medical-imaging.ap-southeast-2.amazonaws.com"
    }
  }

  lifecycle {
    ignore_changes = [
      source_code_hash,
      filename
    ]
  }
}

resource "aws_cloudwatch_log_group" "signer_lambda" {
  name = "/aws/lambda/${aws_lambda_function.signer_lambda.function_name}"
  retention_in_days = 30
}

#
# API Gateway
#

# Define name for API Gateway, and set protocol to HTTP
resource "aws_apigatewayv2_api" "signer_lambda" {
  name          = var.api_gateway_name
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "signer_lambda_endpoint" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.signer_lambda.name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_stage" "signer_lambda_dev" {
  api_id = aws_apigatewayv2_api.signer_lambda.id
  name        = "development_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.signer_lambda_endpoint.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

# Connect API Gateway to Lambda function
resource "aws_apigatewayv2_integration" "signer_lambda" {
  api_id = aws_apigatewayv2_api.signer_lambda.id
  integration_uri    = aws_lambda_function.signer_lambda.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

# Map HTTP Request to target - Gateway -> Route -> Target (API Gateway Integration)
resource "aws_apigatewayv2_route" "signer_lambda" {
  api_id = aws_apigatewayv2_api.signer_lambda.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.signer_lambda.id}"
}

resource "aws_lambda_permission" "signer_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.signer_lambda.arn
  principal     = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.signer_lambda.execution_arn}/*/*"
}

# [import for development branch] api.dev.viewer.curvebeamai.com
# resource "aws_apigatewayv2_domain_name" "access_token_endpoint" {
#   domain_name = "api.${var.domain_name}"

#   domain_name_configuration {
#     certificate_arn = var.ssl_cert_aus_arn
#     endpoint_type   = "REGIONAL"
#     security_policy = "TLS_1_2"
#   }
# }

# # A record to route requests to owned domain
# # [import for development branch] Z00423272G8YD6OSGHZCE_api.dev.viewer.curvebeamai.com_A
# resource "aws_route53_record" "access_token_endpoint" {
#   zone_id = var.domain_zone_id
#   name    = "api.${var.domain_name}"
#   type    = "A"
#   alias {
#       evaluate_target_health = true
#       name                   = aws_apigatewayv2_domain_name.access_token_endpoint.domain_name_configuration[0].target_domain_name
#       zone_id                = aws_apigatewayv2_domain_name.access_token_endpoint.domain_name_configuration[0].hosted_zone_id
#   }
# }

# resource "aws_apigatewayv2_api_mapping" "access_token_endpoint" {
#   api_id      = aws_apigatewayv2_api.access_token_endpoint.id
#   domain_name = "api.${var.domain_name}"
#   stage       = aws_apigatewayv2_stage.access_token_endpoint_dev.id
# }
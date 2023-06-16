#0 connect to aws account
provider "aws" {
  region = "us-east-1"
  access_key = "AKIAUTPMHOVVBUFSYGF6"
  secret_key = "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"
}

#1 Create execution role for the lamda function
#### Assume role policy
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }


  }
}

#### Managed policies
resource "aws_iam_policy" "cloudwatchlogs" {
  name = "cloudwatchlogs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_policy" "snsandsespermissions" {
  name = "snsandsespermissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ses:*", "sns:*", "states:*"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

#### Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name                = "lambda_role"
  assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
  managed_policy_arns = [aws_iam_policy.cloudwatchlogs.arn, aws_iam_policy.snsandsespermissions.arn]
}

#2 Create the lambda function
resource "aws_lambda_function" "email_reminder_lambda" {
  filename      = "C:\\Users\\user\\Desktop\\project_serverless\\email_reminder_lambda.zip"
  function_name = "email_reminder_lambda"
  role          = aws_iam_role.lambda_role.arn
  # The field handler is very important, in terraform documentation it is said that it should be "The function entrypoint in your code" 
  # Dont be mistaken, the value of the handler is not only the name of the function, It should be instead comprised of:
  # -The name of the file in which the Lambda handler function is located
  # -The name of the Python handler function
  # The following field will generate this error message when invoking the lambda function => "Bad handler 'lambda_handler': not enough values to unpack (expected 2, got 1)"
  # handler       = "lambda_handler"
  # Solution discussed on this thread https://stackoverflow.com/questions/69780574/why-do-i-get-a-bad-handler-aws-lambda-not-enough-values-to-unpack-error
  # Credit goes to Ermiya Eskandary :)
  handler       = "lambda_function.lambda_handler" 
  runtime = "python3.9"
}

#3 Implement the state machine

#### Create role for state machine

######## Assume role policy
data "aws_iam_policy_document" "state_machine_assume_role_policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }


  }
}

######## Managed policies
resource "aws_iam_policy" "cloudwatchlogs_state_machine" {
  name = "cloudwatchlogs_state_machine"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
          "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_policy" "invokelambdasandsendsns" {
  name = "invokelambdasandsendsns"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["lambda:InvokeFunction", "sns:*"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

######## state machine role
resource "aws_iam_role" "state_machine_role" {
  name                = "state_machine_role"
  assume_role_policy  = data.aws_iam_policy_document.state_machine_assume_role_policy.json
  managed_policy_arns = [aws_iam_policy.cloudwatchlogs_state_machine.arn, aws_iam_policy.invokelambdasandsendsns.arn]
}


######## Create state machine
resource "aws_sfn_state_machine" "MyStateMachine" {
  name     = "MyStateMachine"
  role_arn = aws_iam_role.state_machine_role.arn

  definition = <<EOF
{
  "Comment": "A Hello World example of the Amazon States Language using an AWS Lambda Function",
  "StartAt": "Timer",
  "States": {
    "Timer": {
      "Type": "Wait",
      "SecondsPath": "$.waitSeconds",
      "Next": "Email"
    },
    "Email": {
      "Type" : "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.email_reminder_lambda.arn}",
        "Payload": {
          "Input.$": "$"
        }
      },
      "Next": "NextState"
    },
    "NextState": {
      "Type": "Pass",
      "End": true
    }
  }
}
EOF
}


#4 Create the api lambda function
resource "aws_lambda_function" "api_lambda" {
  filename      = "C:\\Users\\user\\Desktop\\project_serverless\\api_lambda.zip"
  function_name = "api_lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime = "python3.9"
  depends_on = [aws_sfn_state_machine.MyStateMachine]
}

#5 Implementing the client-side application

#### Create the S3 bucket
resource "aws_s3_bucket" "gyminstructions789789" {
  bucket = "gyminstructions789789"
  #block public access option will be unticked
}

#### Making the S3 bucket publically accessible via a bucket policy and via removing the option block all public access
resource "aws_s3_bucket_public_access_block" "remove_block_all_public_access" {
  bucket = aws_s3_bucket.gyminstructions789789.id
  ## The following options will have these default values
  #block_public_acls       = false
  #block_public_policy     = false
  #ignore_public_acls      = false
  #restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.gyminstructions789789.id
  policy = data.aws_iam_policy_document.allow_public_access.json
}

data "aws_iam_policy_document" "allow_public_access" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.gyminstructions789789.arn}/*",
    ]
  }
}

#### Enabling static website hosting for the S3 bucket
resource "aws_s3_bucket_website_configuration" "allow_static_website_hosting" {
  bucket = aws_s3_bucket.gyminstructions789789.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }

}

#5 Implementing the gateway api manually with cors enabled
#6 Inject api endpoint in the file serverless.js of the directory serverless_frontend and upload all files in this directory to the S3 bucket

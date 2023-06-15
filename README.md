# AWS Serverless Application
In this project we are going to implement a simple serverless application using **S3**, **API Gateway** , **Lambda** , **Step Functions**  and **SES** .  
The serverless application has been created mainly using **aws**  and **python** .  
The serverless application has been automated using **Terraform** .  
The goal of the serverless application is to enable our trainer to send us training instructions in order to guide us through our muscle gaining journey.

This project consists of 6 stages :
- STAGE 1 : Configure Simple Email service (SES)
- STAGE 2 : Add a email lambda function to use SES to send emails for the serverless application 
- STAGE 3 : Implement and configure the state machine, the core of the application
- STAGE 4 : Implement the supporting lambda function for the API Gateway
- STAGE 5 : Implement the S3 bucket 
- STAGE 6 : Create the API Gateway 
- STAGE 7 : Import the static frontend application to the S3 bucket
- STAGE 8 : Test functionality
- STAGE 9 : Cleanup the account

Before starting, we need to be sure that we are logged into an AWS account, have admin privileges and are in the `us-east-1` / `N. Virginia` Region.  
Here is the terraform code
```terraform
provider "aws" {
  region = "us-east-1"
  access_key = "Access_Key_Example"
  secret_key = "Secret_Key_Example"
}
```

# STAGE 1 - Configure Simple Email service (SES)
The Gym Instructions application is going to send reminder messages via Email. It will use the simple email service or SES. In production, it will be configured to allow sending from the application email, to any users of the application.  
In order to be able to send to/from an email address, we need to verify that said address.  
For our application email:
- the email the app (used by the trainer) will send from is going to be `moomenabid97+trainer@gmail.com`
- the email for the customer (used by the trainee) is  `moomenabid97+trainee@gmail.com` 

```terraform
#1 mail creation
resource "aws_ses_email_identity" "moomenabid97trainer" {
  email = "moomenabid97+trainer@gmail.com"
}

resource "aws_ses_email_identity" "moomenabid97trainee" {
  email = "moomenabid97+trainee@gmail.com"
}
```
# STAGE 2 : Add a email lambda function to use SES to send emails for the serverless application
## STAGE 2A - CREATE THE Lambda Execution Role for Lambda
In this stage, we need to create an IAM role which the email_reminder_lambda function will use to interact with other AWS services.
```terraform
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
```
Now we have an execution role that provides SES, SNS and Logging permissions to whatever assumes this role.  
This role is what gives lambda the permissions to interact with those services.

Next we are going to create the lambda function which will be used by the serverless application to create an email and then send it using `SES`

## STAGE 2B - Create the python zip package to be executed by the email_reminder_lambda function
First, we need tp create the python zip package to be executed by the email_reminder_lambda function  
We need to do this step manually, we will afterwards download the zip package and use to create the lambda function automatically with terraform.

In order to do so, we need to:  
Move to the lambda console https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions  
Click on `Create Function`  
Select `Author from scratch`  
For `Function name` enter `email_reminder_lambda`  
and for runtime click the dropdown and pick `Python 3.9`  
Expand `Change default execution role`  
Pick to `Use an existing Role`  
Click the `Existing Role` dropdown and pick `lambda_role` 
Click `Create Function`  

Then, we scrolled down to `Function code` and in the `lambda_function` code box, we wrote this code
```python
import boto3, os, json

FROM_EMAIL_ADDRESS = 'moomenabid97+trainer@gmail.com'

ses = boto3.client('ses')

def lambda_handler(event, context):
    # Print event data to logs .. 
    print("Received event: " + json.dumps(event))
    
    ses.send_email( 
        Source=FROM_EMAIL_ADDRESS,
        Destination={ 'ToAddresses': [ event['Input']['email'] ] }, 
        Message={ 'Subject': {'Data': 'Your trainer demands your attention!'},
            'Body': {'Text': {'Data': event['Input']['message']}}
        }
    )
    return 'Success!'
```
What this functio does is that it will send an email to an address it's supplied with (by step functions) and it will be FROM the email address we specified in the variable FROM_EMAIL_ADDRESS.

Finally, we deployed the function, then we downloaded it's zip package and finally we deleted it because we will be creating it automatically with terraform using the downloaded zip package.

## STAGE 2C - Create the email_reminder_lambda function
Once the zip package is downloaded, we deploy the email_reminder_lambda function using the following terraform code.
```terraform
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
```
## STAGE 2 - FINISH   
At this point you have configured the lambda function which will be used eventually to send emails on behalf of the serverless application.    

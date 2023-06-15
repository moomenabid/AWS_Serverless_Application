# AWS Serverless Application
In this project we are going to implement a simple serverless application using S3, API Gateway, Lambda, Step Functions and SES.  
The serverless application has been created mainly using aws and python.
The serverless application has been automated using Terraform.
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









# AWS Serverless Application
In this project we are going to implement a simple serverless application using **S3**, **API Gateway** , **Lambda** , **Step Functions**  and **SES** .  
The serverless application has been created mainly using **AWS**  and **Python** .  
The serverless application has been automated using **Terraform** .  
The goal of the serverless application is to enable our trainer to send us training instructions in order to guide us through our muscle gaining journey.

This project consists of 6 stages :
- STAGE 1 : Configure Simple Email service (SES)
- STAGE 2 : Add a email lambda function to use SES to send emails for the serverless application 
- STAGE 3 : Implement and configure the state machine, the core of the application
- STAGE 4 : Implement the supporting lambda function for the API Gateway
- STAGE 5 : Create the API Gateway  
- STAGE 6 : Implement the static frontend application and test functionality
- STAGE 7 : Cleanup the account


Before starting, we need to be sure that we have terraform installed in our local machine, we are logged into an AWS account, have admin privileges (we need to donwload the corresponding access_key and secret_key and use them within our terraform code) and are in the `us-east-1` / `N. Virginia` Region.  
Here is the corresponding terraform code
```terraform
provider "aws" {
  region = "us-east-1"
  access_key = "Access_Key_Example" # we cannot expose our access key and secret key for security reasons
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
## STAGE 2A - Create the Lambda Execution Role for Lambda
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
What this function does is that it will send an email to an address it's supplied with (by step functions) and it will be FROM the email address we specified in the variable FROM_EMAIL_ADDRESS.

Finally, we deployed the function, then we downloaded it's zip package `email_reminder_lambda.zip` and finally we deleted it because we will be creating it automatically with terraform using the downloaded zip package.

## STAGE 2C - Create the email_reminder_lambda function
Once the zip package `email_reminder_lambda.zip` is downloaded, we deploy the email_reminder_lambda function using the following terraform code.
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
## STAGE 2D - Finish   
At this point you have configured the lambda function which will be used eventually to send emails on behalf of the serverless application. 
# STAGE 3 : Implement and configure the state machine, the core of the application
## STAGE 3A - Create the state machine's role
In this stage we need to create an IAM role which the state machine will use to interact with other AWS services.  
```terraform
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

```

If we move to the IAM Console https://console.aws.amazon.com/iam/home?#/roles and review the state machine role, we can see that it gives 
- logging permissions
- the ability to invoke the email lambda function when it needs to send emails
- the ability to use SNS to send text messages

## STAGE 3B - Create the state machine
The state machine will control the flow through the serverless application.. once stated it will coordinate other AWS services as required.  
Here is what the state machine is going to do
- The state machine starts
- Then waits for a certain time period based on the `Timer` state (This is controlled by the web front end which we will deploy soon)
- Then the `email_lambda_function` is invoked which sends an email reminder  
Here is the terraform code we used to deploy the state machine
```terraform
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
```
## STAGE 3C - FINISH
At this point we have configured the state machine which is the core part of the serverless application.  
The state machine controls the flow through the application and is responsible for interacting with other AWS products and services.  

# STAGE 4 : Implement the supporting lambda function for the API Gateway
From now on, we will be creating the front end API for the serverless application.  
The front end loads from S3, runs in a browser and communicates with this API.  
It uses API Gateway for the API Endpoint, and this uses Lambda to provide the backing compute.  
First we will create the supporting `API_LAMBDA` and then the `API Gateway`  
## STAGE 4A : Create the python zip package to be executed by the api_lambda function
First, we need to create the python zip package to be executed by the api_lambda function  
We need to do this step manually, we will afterwards download the zip package and use to create the lambda function automatically with terraform.

In order to do so, we need to: 
Move to the Lambda console https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions  
Click on `Create Function`  
for `Function Name` use `api_lambda`  
for `Runtime` use `Python 3.9`  
Expand `Change default execution role`  
Select `Use an existing role`  
Choose the `lambda_role` from the dropdown  
Click `Create Function`  

Then, we scrolled down to `Function code` and in the `lambda_function` code box, we wrote this code
```python
import boto3, json, os, decimal

#Getting state machine arn
sm = boto3.client('stepfunctions')
sm_list_response = sm.list_state_machines()
sm_list = sm_list_response['stateMachines']

sm_target = {}
for e in sm_list:
    if e["name"] == "MyStateMachine":
        sm_target = e.copy()
        break

SM_ARN = sm_target['stateMachineArn']

def lambda_handler(event, context):
    # Print event data to logs .. 
    print("Received event: " + json.dumps(event))

    # Load data coming from APIGateway
    data = json.loads(event['body'])
    data['waitSeconds'] = int(data['waitSeconds'])
    
    # Sanity check that all of the parameters we need have come through from API gateway
    checks = []
    checks.append('waitSeconds' in data)
    checks.append(type(data['waitSeconds']) == int)
    checks.append('message' in data)

    # if any checks fail, return error to API Gateway to return to client
    if False in checks:
        response = {
            "statusCode": 400,
            "headers": {"Access-Control-Allow-Origin":"*"},
            "body": json.dumps( { "Status": "Success", "Reason": "Input failed validation" })
        }
    # If none, start the state machine execution and inform client of 2XX success :)
    else: 
        sm.start_execution( stateMachineArn=SM_ARN, input=json.dumps(data) )
        response = {
            "statusCode": 200,
            "headers": {"Access-Control-Allow-Origin":"*"},
            "body": json.dumps( {"Status": "Success"})
        }
    return response
```
This is the lambda function which will support the API Gateway  
This is the function which will provide compute to API Gateway.  
It's job is to be called by API Gateway when its used by the serverless front end part of the application (loaded by S3), It accepts some information from you, via API Gateway and then it starts a state machine execution - which is the logic of the application.

Finally, we deployed the function, then we downloaded it's zip package `api_lambda.zip` and finally we deleted it because we will be creating it automatically with terraform using the downloaded zip package.

## STAGE 4B : Create the api_lambda function
Once the zip package `api_lambda.zip` is downloaded, we deploy automatically the api_lambda function using the following terraform code.
```terraform
#4 Create the api lambda function
resource "aws_lambda_function" "api_lambda" {
  filename      = "C:\\Users\\user\\Desktop\\project_serverless\\api_lambda.zip"
  function_name = "api_lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime = "python3.9"
  depends_on = [aws_sfn_state_machine.MyStateMachine]
}
```
# STAGE 5 : Create the API Gateway
Now we have the api_lambda function created, the next step is to create the API Gateway, API and Method which the front end part of the serverless application will communicate with.
## STAGE 5A : Create the API Gateway
In order to do so we need to:
- Move to the API Gateway console https://console.aws.amazon.com/apigateway/main/apis?region=us-east-1  
- Click `APIs` on the menu on the left  
- Locate the `REST API` box, and click `Build`  
- Under `Create new API` ensure `New API` is selected, For `API name*` enter `gyminstructions`, for `Endpoint Type` pick `Regional`, Click `create API` 
## STAGE 5B : Create the resource
In order to do so we need to:
- Click the Actions dropdown and Click Create Resource
- Under resource name, enter gyminstructions
- Click Create Resource
## STAGE 5C : Create the method
In order to do so we need to:  
Ensure we have the `/gyminstructions` resource selected, click `Actions` dropdown and click `create method`  
In the small dropdown box which appears below `/gyminstructions` select `POST` and click the `tick` symbol next to it.  
this method is what the front end part of the application will make calls to.  
Its what the api_lambda will provide services for. 

we then:
Ensure for `Integration Type` that `Lambda Function` is selected.  
Make sure `us-east-1` is selected for `Lambda Region`  
In the `Lambda Function` box, type `api_lambda`, click `Save`  

## STAGE 5D - DEPLOY API  

Now the API, Resource and Method are configured - we now need to deploy the API out to API gateway, specifically an API Gateway STAGE.  
Here is how we do it:
Click `Actions` Dropdown and `Deploy API`  
For `Deployment Stage` select `New Stage`  
for stage name and stage description enter `prod`  
Click `Deploy`  

At the top of the screen will be an `Invoke URL`, we will need it in the next STAGE.  
This URL will be used by the client side component of the serverless application.    
## STAGE 5E - Finish
At this point we have configured the last part of the AWS side of the serveless application.   
We now have :-

- SES Configured
- An Email Lambda function to send email using SES
- A State Machine configured which can send EMAIL after a certain time period when invoked.
- An API, Resource & Method, which use a lambda function for backing deployed out to the PROD stage of API Gateway

In STAGES 6 and 7, we will configure the client side of the application (loaded from S3, running in a browser) so that it communicates to API Gateway.  

# STAGE 6 : Implement the static frontend application and test functionality
In this stage of the application we will create an S3 bucket and static website hosting which will host the application front end.  
We will download the source files for the front end, configure them to connect to your specific API gateway and then upload them to S3.
Finally, we will run some application tests to verify its functionality. 
## STAGE 6A - Create the S3 bucket
We createthe S3 bucket by applying the following terraform code
```terraform
#5 Implementing the client-side application

#### Create the S3 bucket
resource "aws_s3_bucket" "gyminstructions789789" {
  bucket = "gyminstructions789789"
  #block public access option will be unticked
}
```
Then, and in order to make the S3 bucket public, we need to **UNTICK** the option `Block all public access` available in the S3 console  
We do this via the following terraform code
```terraform
#### Making the S3 bucket publically accessible via a bucket policy and via removing the option block all public access
resource "aws_s3_bucket_public_access_block" "remove_block_all_public_access" {
  bucket = aws_s3_bucket.gyminstructions789789.id
  ## The following options will have these default values
  #block_public_acls       = false
  #block_public_policy     = false
  #ignore_public_acls      = false
  #restrict_public_buckets = false
}
```
## STAGE 6B - Set the S3 bucket as public
In order to make the S3 bucket public, we need to associate a `bucket policy` to it  
We do it by applying the following terraform code
```terraform
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
```
## STAGE 6C - Enable Static Hosting
Next we need to enable static hosting on the S3 bucket so that it can be used as a front end website.  
We do it by applying the following terraform code
```terraform
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
```
At this point we can access the bucket URL under the `Properties Tab`, under `Bucket Website Endpoint`  

## STAGE 6D - Download and edit the front end files
Inside the serverless_frontend folder in this repository are the front end files for the serverless website :

- index.html .. the main index page
- main.css .. the stylesheet for the page
- personal_trainer.png .. an image of of the trainer
- serverless.js .. the JS code which runs in a browser. It responds when buttons are clicked, and passes and text from the boxes when it calls the API Gateway endpoint. 

Then we need to:  
Open the `serverless.js` in a code/text editor.
Locate the placeholder `REPLACEME_API_GATEWAY_INVOKE_URL` . replace it with your API Gateway Invoke URL
at the end of this URL.. add `/gyminstructions`
it should look something like this `https://somethingsomething.execute-api.us-east-1.amazonaws.com/prod/gyminstructions` 
Save the file.  
## STAGE 6E - Upload and test
In order to do this, we need to:  
Return to the S3 console
Click on the `Objects` Tab.  
Click `Upload`  
Drag the 4 files from the serverless_frontend folder onto this tab, including the serverless.js file we just edited.  
Click `Upload` and wait for it to complete.  

Then, we:  
Open the `GymInstructions URL` we just noted down in a new tab. 
What we are seeing is a simple HTML web page created by the HTML file itself and the `main.css` stylesheet.
When we click buttons .. that calls the `.js` file which is the starting point for the serverless application

Ok to test the application we:  
Enter an amount of time to wait for before sending the next instruction ... for example `120` seconds
Enter a message, for example `do 100 push ups`  
then enter the `trainee Address` in the email box, this is the email which we verified right at the start as the customer for this application which is moomenabid97+trainee@gmail.com  
**before we do the next step and click the button on the application, if we want to see how the application works we do the following**
open a new tab to the `Step functions console` https://console.aws.amazon.com/states/home?region=us-east-1#/statemachines  
Click on `gyminstructions`  
Click on the `Logging` tab, we will see no logs
CLick on the `Executions` tab, we will see no executions..

we move back to the web application tab (s3 bucket)  
then click on `Email Trainee` Button to send an email.  

In order to see executions, here is what we we will do:  
Got back to the Step functions console
make sure the `Executions` Tab is selected
click the `Refresh` Icon
Click the `execution`  
Watch the graphic .. see how the `Timer state` is highlighted
The step function is now executing and it has its own state ... its a serverless flow.
If we Keep waiting, and after 120 seconds the visual will update showing the flow through the state machine  

- Timer .. waits 120 seconds
- `Email` invokes the lambda function to send an email
- `NextState` in then moved through, then finally `END`

If we scroll to the top, click `ExeuctionInput` and we can see the information entered on the webpage.
This was send it, via the `JS` running in browser, to the API gateway, to the `api_lambda` then through to the `statemachine`  

If we click `gyminstructions` at the top of the page  
Click on the `Logging` Tab  
Because the roles we created had `CWLogs` permissions the state machine is able to log to CWLogs
Review the logs and ensure we are happy with the flow.  
## STAGE 6F - Finish
At this point thats everything .. we now have a fully functional serverless application that does the following

- Loads HTML & JS From S3 & Static hosting
- Communicates via `JS` to API Gateway 
- uses `api_lambda` as backing resource
- runs a statemachine passing in parameters
- state machine sends email
- state machine terminates

No servers were harmed, or used even, in this production 

Thats everything for this project, in the next and final stage STAGE7 we will clear up all of the services used for this project.  
## STAGE 7 - Cleanup the account
In this stage you will cleanup all the resources created by this project  
To do this, we need to:  

Move to the S3 console https://s3.console.aws.amazon.com/s3/home?region=us-east-1 Select the bucket we created
Click Empty, type or copy/paste the bucket name and click Empty, Click Exit

Move to the API Gateway console https://console.aws.amazon.com/apigateway/main/apis?region=us-east-1
Check the box next to the petcuddleotron API
Click Actions and then Delete
Click Delete

Then we need to go into each of the directories named terraform_script_email_identities and terraform_script_serverless_application_backend and execute the following command
```powershell
terraform destroy -auto-approve
```

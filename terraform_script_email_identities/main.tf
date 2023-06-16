#0 connect to aws account
provider "aws" {
  region = "us-east-1"
  access_key = "AKIAUTPMHOVVBUFSYGF6"
  secret_key = "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"
}

#1 mail creation
resource "aws_ses_email_identity" "moomenabid97trainer" {
  email = "moomenabid97+trainer@gmail.com"
}

resource "aws_ses_email_identity" "moomenabid97trainee" {
  email = "moomenabid97+trainee@gmail.com"
}

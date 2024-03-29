terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.40"
    }
  }
}

# Define the providers block for AWS
provider "aws" {
  region = "eu-central-1"
  alias  = "frankfurt"
}
/*
provider "aws" {
  region = "us-east-2"
  alias  = "ohio"
}
*/

# Define deploy key
resource "aws_key_pair" "deploy" {
  provider   = aws.frankfurt # Refer to the aliased provider
  key_name   = "deploy-key"
  public_key = file("./public_keys/id_rsa_starter_kit_deploy.pub")
  # make terraform import aws_key_pair.deploy deploy-key
}

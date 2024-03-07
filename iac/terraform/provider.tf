terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.31.0"
    }
  }
}

# Define the provider block for AWS
/*
provider "aws" {
  region = "eu-central-1"
}
*/

provider "aws" {
  region = "us-east-2"
}

# Define deploy key
resource "aws_key_pair" "deploy" {
  key_name   = "deploy-key"
  public_key = file("../public_keys/id_rsa.pub")
  # ssh ubuntu@ip - for ubuntu
  # make terraform import aws_key_pair.deploy deploy-key
}

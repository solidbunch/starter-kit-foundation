terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.95"
    }
  }
}

# Define the providers block for AWS
provider "aws" {
  region = "eu-west-1"
}

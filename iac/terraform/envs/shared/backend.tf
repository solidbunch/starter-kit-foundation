terraform {
  # Configure backend to store Terraform state in an S3 bucket and use DynamoDB for locking
  backend "s3" {
    bucket         = "starter-kit-io-terraform-state-storage"   # Name of the S3 bucket where Terraform state will be stored
    key            = "envs/shared/network.tfstate"              # Path to the state file in the bucket
    region         = "eu-west-1"                                # AWS region where the S3 bucket is located
    dynamodb_table = "terraform-locks"                          # DynamoDB table for state locking to prevent conflicts
    encrypt        = true                                       # Enable server-side encryption for the state file
  }
}

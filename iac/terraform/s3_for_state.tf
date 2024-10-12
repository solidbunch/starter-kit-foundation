terraform {
  # Configure backend to store Terraform state in an S3 bucket and use DynamoDB for locking
  backend "s3" {
    bucket         = "your-unique-bucket-name"  # Name of the S3 bucket where Terraform state will be stored
    key            = "terraform/state/terraform.tfstate"  # Path to the state file in the bucket
    region         = "us-west-2"  # AWS region where the S3 bucket is located
    dynamodb_table = "your-dynamodb-table-name"  # DynamoDB table for state locking to prevent conflicts
    encrypt        = true  # Enable server-side encryption for the state file
  }
}

# Create an S3 bucket to store Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "your-unique-bucket-name"  # Unique name of the S3 bucket
}

# Configure ownership controls for the S3 bucket to manage object ownership
resource "aws_s3_bucket_ownership_controls" "ownership_controls" {
  bucket = aws_s3_bucket.terraform_state.id  # Reference to the S3 bucket

  rule {
    object_ownership = "BucketOwnerPreferred"  # Define object ownership policy
  }
}

# Configure public access block to restrict public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.terraform_state.id  # Reference to the S3 bucket
  block_public_acls       = true  # Block public ACLs
  block_public_policy     = true  # Block public policies
  ignore_public_acls      = true  # Ignore public ACLs if set
  restrict_public_buckets = true  # Restrict public access to the bucket
}

# Define ACL (Access Control List) for the S3 bucket using a separate resource
resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.terraform_state.id  # Reference to the S3 bucket
  acl    = "private"  # Set ACL to private

  # Dependencies to ensure ownership and public access rules are applied first
  depends_on = [
    aws_s3_bucket_ownership_controls.ownership_controls,
    aws_s3_bucket_public_access_block.public_access,
  ]
}

# Enable versioning for the S3 bucket to protect against overwriting state files
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state.id  # Reference to the S3 bucket

  versioning_configuration {
    status = "Enabled"  # Enable versioning to keep track of file versions
  }
}

# Create a DynamoDB table to implement state locking to avoid race conditions
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "your-dynamodb-table-name"  # Unique name of the DynamoDB table
  billing_mode = "PAY_PER_REQUEST"  # Pay only for the requests made

  hash_key = "LockID"  # Define LockID as the primary key

  # Define the attributes for the table
  attribute {
    name = "LockID"
    type = "S"  # LockID is a string type attribute
  }
}

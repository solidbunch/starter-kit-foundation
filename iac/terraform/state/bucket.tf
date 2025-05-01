# Create an S3 bucket to store Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "starter-kit-io-terraform-state-storage"  # Unique name of the S3 bucket
}

# Configure public access block to restrict public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.terraform_state.id  # Reference to the S3 bucket
  block_public_acls       = true  # Block public ACLs
  block_public_policy     = true  # Block public policies
  ignore_public_acls      = true  # Ignore public ACLs if set
  restrict_public_buckets = true  # Restrict public access to the bucket
}

# Enable versioning for the S3 bucket to protect against overwriting state files
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state.id  # Reference to the S3 bucket

  versioning_configuration {
    status = "Enabled"  # Enable versioning to keep track of file versions
  }
}

# Configure lifecycle rules to delete noncurrent object versions older than 1 year
resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"


    filter {
      prefix = ""  # apply to all objects in the bucket
      # prefix = "envs/dev/" # apply to objects in the envs/dev/ directory
    }

    noncurrent_version_expiration {
      noncurrent_days = 365  # Delete noncurrent versions older than 365 days
    }
  }
}

# Create a DynamoDB table to implement state locking to avoid race conditions
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"  # Pay only for the requests made

  hash_key = "LockID"  # Define LockID as the primary key

  # Define the attributes for the table
  attribute {
    name = "LockID"
    type = "S"  # LockID is a string type attribute
  }
}

# ToDo add Lifecycle Policies

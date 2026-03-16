provider "aws" {
  region = "us-east-1"
}

# Example S3 bucket
resource "aws_s3_bucket" "demo_bucket" {
  bucket = "rahul-terraform-ai-demo-bucket-12345"

  tags = {
    Name        = "TerraformAIDemo"
    Environment = "QA"
  }
}

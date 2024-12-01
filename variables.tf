# variables.tf
variable "environment" {
  description = "Deployment environment (test or production)"
}

variable "instance_count" {
  description = "Number of EC2 instances"
  default     = 2  # Default for test environment
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
}

variable "instance_type" {
  description = "Type of EC2 instance"
  default     = "t3.medium"
}

variable "key_name" {
  description = "SSH key pair name"
}

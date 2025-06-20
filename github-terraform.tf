terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

# Configure the GitHub Provider
provider "github" {
  token = var.github_token  # Changed from literal to variable reference
}

/*resource "github_repository" "example" {
  name        = "example"
  description = "My awesome codebase"

  visibility = "public"

}*/
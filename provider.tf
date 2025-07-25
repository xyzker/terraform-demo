terraform {
  cloud {
    organization = "xyzker"

    workspaces {
      name = "terraform-demo"
    }
  }

  required_providers {
/*    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }*/

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
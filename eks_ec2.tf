# Minimal EKS configuration with t2.micro instance
# Uses public subnets to avoid NAT Gateway costs

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "minimal-eks-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "minimal-eks-igw"
  }
}

# Public Subnets (minimum 2 for EKS requirement)
resource "aws_subnet" "eks_subnet_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "minimal-eks-subnet-a"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "eks_subnet_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "minimal-eks-subnet-b"
    "kubernetes.io/role/elb" = "1"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "eks_public_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "minimal-eks-public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "eks_rta_a" {
  subnet_id      = aws_subnet.eks_subnet_a.id
  route_table_id = aws_route_table.eks_public_rt.id
}

resource "aws_route_table_association" "eks_rta_b" {
  subnet_id      = aws_subnet.eks_subnet_b.id
  route_table_id = aws_route_table.eks_public_rt.id
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "minimal-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "minimal_eks" {
  name     = "minimal-eks"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.33"

  vpc_config {
    subnet_ids              = [aws_subnet.eks_subnet_a.id, aws_subnet.eks_subnet_b.id]
    endpoint_private_access = false
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = {
    Name = "minimal-eks-cluster"
  }
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_node_role" {
  name = "minimal-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# Minimal EKS Node Group with single t2.micro instance
resource "aws_eks_node_group" "minimal_nodes" {
  cluster_name    = aws_eks_cluster.minimal_eks.name
  node_group_name = "minimal-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.eks_subnet_a.id]  # Single subnet to ensure single node

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = ["t2.micro"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker_policy,
    aws_iam_role_policy_attachment.eks_node_cni_policy,
    aws_iam_role_policy_attachment.eks_node_registry_policy,
  ]

  tags = {
    Name = "minimal-eks-node"
  }
}

# --- IRSA Configuration (Same as before) ---

# Get cluster info for OIDC
data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.minimal_eks.name
}

data "tls_certificate" "eks_oidc_thumbprint" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc_thumbprint.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  tags = {
    Name = "minimal-eks-oidc"
  }
}

# S3 List Policy
resource "aws_iam_policy" "s3_list_policy" {
  name        = "MinimalEKSS3ListPolicy"
  description = "Allow listing S3 buckets for minimal EKS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:ListAllMyBuckets"]
      Resource = "*"
    }]
  })
}

# IAM Role for Service Account
resource "aws_iam_role" "eks_s3_service_account_role" {
  name = "minimal-eks-s3-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:default:s3-service-account"
          "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "eks_s3_policy_attachment" {
  policy_arn = aws_iam_policy.s3_list_policy.arn
  role       = aws_iam_role.eks_s3_service_account_role.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.minimal_eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.minimal_eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.minimal_eks.token
}

data "aws_eks_cluster_auth" "minimal_eks" {
  name = aws_eks_cluster.minimal_eks.name
}

# Kubernetes Service Account
resource "kubernetes_service_account" "s3_service_account" {
  metadata {
    name      = "s3-service-account"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.eks_s3_service_account_role.arn
    }
  }

  depends_on = [aws_eks_node_group.minimal_nodes]
}

# Test Pod with AWS CLI
resource "kubernetes_pod" "aws_cli_test" {
  metadata {
    name      = "aws-cli-test"
    namespace = "default"
  }

  spec {
    service_account_name = kubernetes_service_account.s3_service_account.metadata[0].name

    container {
      name    = "aws-cli"
      image   = "amazon/aws-cli:2.15.0"
      command = ["sleep", "3600"]

      # Resource limits for t2.micro
      resources {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"    # Reduced from 100m
          memory = "64Mi"   # Reduced from 128Mi
        }
      }
    }

    restart_policy = "Always"
  }

  depends_on = [
    kubernetes_service_account.s3_service_account,
    aws_eks_node_group.minimal_nodes
  ]
}

# Outputs
output "cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.minimal_eks.name
}

output "cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = aws_eks_cluster.minimal_eks.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.minimal_eks.vpc_config[0].cluster_security_group_id
}

output "node_group_arn" {
  description = "EKS Node Group ARN"
  value       = aws_eks_node_group.minimal_nodes.arn
}

output "service_account_role_arn" {
  description = "IAM Role ARN for Service Account"
  value       = aws_iam_role.eks_s3_service_account_role.arn
}
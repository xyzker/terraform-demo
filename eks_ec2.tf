resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eks-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  }
}

# Public Subnets for NAT Gateways
resource "aws_subnet" "eks_public_subnet_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet-a"
  }
}

resource "aws_subnet" "eks_public_subnet_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet-b"
  }
}

# Private Subnets for EKS Nodes
resource "aws_subnet" "eks_subnet_a" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "eks-private-subnet-a"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "eks_subnet_b" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "eks-private-subnet-b"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "eks_nat_a" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.eks_igw]

  tags = {
    Name = "eks-nat-eip-a"
  }
}

resource "aws_eip" "eks_nat_b" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.eks_igw]

  tags = {
    Name = "eks-nat-eip-b"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "eks_nat_a" {
  allocation_id = aws_eip.eks_nat_a.id
  subnet_id     = aws_subnet.eks_public_subnet_a.id
  depends_on    = [aws_internet_gateway.eks_igw]

  tags = {
    Name = "eks-nat-gateway-a"
  }
}

resource "aws_nat_gateway" "eks_nat_b" {
  allocation_id = aws_eip.eks_nat_b.id
  subnet_id     = aws_subnet.eks_public_subnet_b.id
  depends_on    = [aws_internet_gateway.eks_igw]

  tags = {
    Name = "eks-nat-gateway-b"
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
    Name = "eks-public-route-table"
  }
}

# Route Table Associations for Public Subnets
resource "aws_route_table_association" "eks_public_rta_a" {
  subnet_id      = aws_subnet.eks_public_subnet_a.id
  route_table_id = aws_route_table.eks_public_rt.id
}

resource "aws_route_table_association" "eks_public_rta_b" {
  subnet_id      = aws_subnet.eks_public_subnet_b.id
  route_table_id = aws_route_table.eks_public_rt.id
}

# Route Tables for Private Subnets
resource "aws_route_table" "eks_private_rt_a" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat_a.id
  }

  tags = {
    Name = "eks-private-route-table-a"
  }
}

resource "aws_route_table" "eks_private_rt_b" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat_b.id
  }

  tags = {
    Name = "eks-private-route-table-b"
  }
}

# Route Table Associations for Private Subnets
resource "aws_route_table_association" "eks_private_rta_a" {
  subnet_id      = aws_subnet.eks_subnet_a.id
  route_table_id = aws_route_table.eks_private_rt_a.id
}

resource "aws_route_table_association" "eks_private_rta_b" {
  subnet_id      = aws_subnet.eks_subnet_b.id
  route_table_id = aws_route_table.eks_private_rt_b.id
}

# EKS Cluster
resource "aws_eks_cluster" "eks-demo" {
  name     = "demo-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = [aws_subnet.eks_subnet_a.id, aws_subnet.eks_subnet_b.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
  ]
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRole"

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

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# REMOVED: AmazonEKSServicePolicy (deprecated)

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_node_group_role" {
  name = "eksNodeGroupRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

# EKS Managed Node Group
resource "aws_eks_node_group" "demo_node_group" {
  cluster_name    = aws_eks_cluster.eks-demo.name
  node_group_name = "demo-node-group"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = [aws_subnet.eks_subnet_a.id, aws_subnet.eks_subnet_b.id]
  
  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
  
  update_config {
    max_unavailable = 1
  }
  
  instance_types = ["t3.medium"]  # Changed from t2.micro for better performance
  ami_type       = "AL2_x86_64"
  capacity_type  = "ON_DEMAND"

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# --- IRSA for EKS: Service Account with S3 List Permission ---

data "aws_eks_cluster" "eks" {
  name = aws_eks_cluster.eks-demo.name
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks-demo.name
}

data "tls_certificate" "eks_oidc_thumbprint" {
  url = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc_thumbprint.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_policy" "s3_list_policy" {
  name        = "EKSServiceAccountS3ListPolicy"
  description = "Allow listing all S3 buckets."
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:ListBucket"],
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "eks_sa_s3_list" {
  name = "eks-sa-s3-list-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:default:s3-list-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_sa_s3_list_attach" {
  role       = aws_iam_role.eks_sa_s3_list.name
  policy_arn = aws_iam_policy.s3_list_policy.arn
}

resource "kubernetes_service_account" "s3_list_sa" {
  metadata {
    name      = "s3-list-sa"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.eks_sa_s3_list.arn
    }
  }
}

resource "kubernetes_pod" "aws_cli" {
  metadata {
    name      = "aws-cli-pod"
    namespace = "default"
  }
  spec {
    service_account_name = kubernetes_service_account.s3_list_sa.metadata[0].name
    container {
      name    = "aws-cli"
      image   = "amazon/aws-cli:2.15.0"
      command = ["sleep", "3600"]
    }
  }
}
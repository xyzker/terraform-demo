resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"
}
 
resource "aws_subnet" "eks_subnet_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "eks_subnet_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
}

resource "aws_eks_cluster" "eks-demo" {
  name     = "demo-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.eks_subnet_a.id, aws_subnet.eks_subnet_b.id]
  }
}

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

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# --- EKS Managed Node Group ---
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

resource "aws_eks_node_group" "demo_node_group" {
  cluster_name    = aws_eks_cluster.eks-demo.name
  node_group_name = "demo-node-group"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = [aws_subnet.eks_subnet_a.id, aws_subnet.eks_subnet_b.id]
  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }
  instance_types = ["t2.micro"]
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

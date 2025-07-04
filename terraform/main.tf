# Defining Terraform provider and required versions
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# Configuring AWS provider
provider "aws" {
  region = var.aws_region
}

# Configuring Kubernetes provider for EKS
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Configuring Helm provider for EKS
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# Configuring terraform backend
terraform {
  backend "s3" {
    bucket       = "charles-project-55555"
    key          = "eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}




# Creating Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = 2
  tags = {
    Environment = "production"
  }
}

# Creating VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "three-tier-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
  nat_eip_tags           = { for idx, eip in aws_eip.nat : idx => eip.id }

  tags = {
    Environment = "production"
  }
}

# Creating EKS cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  eks_managed_node_groups = {
    main = {
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      instance_types = ["t2.micro"]
      capacity_type  = "ON_DEMAND"
      subnet_ids     = module.vpc.private_subnets
      iam_role_arn   = aws_iam_role.node_role.arn
    }
  }

  tags = {
    Environment = "production"
  }
}

# Creating RDS PostgreSQL instance
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "three-tier-db"
  engine            = "postgres"
  engine_version    = "15.13"
  instance_class    = "db.t4g.medium"
  allocated_storage = 20
  multi_az = true
  db_name  = "appdb"
  username = "appuser"
  port     = 5432
  vpc_security_group_ids = [module.rds_sg.security_group_id]
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name

  storage_encrypted = true
  backup_retention_period = 7
  manage_master_user_password = true
  create_db_parameter_group   = false

  tags = {
    Environment = "production"
  }
}

# Configuring DB subnet group
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "three-tier-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name        = "three-tier-db-subnet-group"
    Environment = "production"
  }
}


# Creating security group for RDS
module "rds_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.1"

  name        = "rds-sg"
  vpc_id      = module.vpc.vpc_id

  ingress_rules       = ["postgresql-tcp"]
  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]

  tags = {
    Environment = "production"
  }
}

# Creating IAM role for EKS cluster
resource "aws_iam_role" "cluster_role" {
  name = "eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}



# Configuring IAM policy for EKS cluster
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Creating IAM role for EKS nodes
resource "aws_iam_role" "node_role" {
  name = "eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}


# Configuring IAM policy for EKS nodes
resource "aws_iam_role_policy_attachment" "node_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}


# Configuring cni policy
resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Configuring ECR policy
resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Creating IAM role for AWS Load Balancer Controller
resource "aws_iam_role" "alb_controller_role" {
  name = "eks-alb-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

# Configuring IAM policy for AWS Load Balancer Controller
resource "aws_iam_role_policy_attachment" "alb_controller_policy" {
  role       = aws_iam_role.alb_controller_role.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

# Installing AWS Load Balancer Controller via Helm
resource "helm_release" "aws_load_balancer_controller" {
  depends_on = [module.eks]
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller_role.arn
  }
}


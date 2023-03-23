provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}


data "aws_iam_policy_document" "this" {
  statement {
    sid       = "AllowAppMesh"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:appmesh:${local.region}:${data.aws_caller_identity.current.account_id}:mesh/*"]

    actions = [
      "appmesh:ListVirtualRouters",
      "appmesh:ListVirtualServices",
      "appmesh:ListRoutes",
      "appmesh:ListGatewayRoutes",
      "appmesh:ListMeshes",
      "appmesh:ListVirtualNodes",
      "appmesh:ListVirtualGateways",
      "appmesh:DescribeMesh",
      "appmesh:DescribeVirtualRouter",
      "appmesh:DescribeRoute",
      "appmesh:DescribeVirtualNode",
      "appmesh:DescribeVirtualGateway",
      "appmesh:DescribeGatewayRoute",
      "appmesh:DescribeVirtualService",
      "appmesh:CreateMesh",
      "appmesh:CreateVirtualRouter",
      "appmesh:CreateVirtualGateway",
      "appmesh:CreateVirtualService",
      "appmesh:CreateGatewayRoute",
      "appmesh:CreateRoute",
      "appmesh:CreateVirtualNode",
      "appmesh:UpdateMesh",
      "appmesh:UpdateRoute",
      "appmesh:UpdateVirtualGateway",
      "appmesh:UpdateVirtualRouter",
      "appmesh:UpdateGatewayRoute",
      "appmesh:UpdateVirtualService",
      "appmesh:UpdateVirtualNode",
      "appmesh:DeleteMesh",
      "appmesh:DeleteRoute",
      "appmesh:DeleteVirtualRouter",
      "appmesh:DeleteGatewayRoute",
      "appmesh:DeleteVirtualService",
      "appmesh:DeleteVirtualNode",
      "appmesh:DeleteVirtualGateway"
    ]
  }

  statement {
    sid       = "CreateServiceLinkedRole"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/appmesh.${data.aws_partition.current.dns_suffix}/AWSServiceRoleForAppMesh"]
    actions   = ["iam:CreateServiceLinkedRole"]

    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["appmesh.${data.aws_partition.current.dns_suffix}"]
    }
  }

  statement {
    sid       = "AllowACMAccess"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:acm:${local.region}:${data.aws_caller_identity.current.account_id}:certificate/*"]
    actions = [
      "acm:ListCertificates",
      "acm:DescribeCertificate",
    ]
  }

  statement {
    sid       = "AllowACMPCAAccess"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:acm-pca:${local.region}:${data.aws_caller_identity.current.account_id}:certificate-authority/*"]
    actions = [
      "acm-pca:DescribeCertificateAuthority",
      "acm-pca:ListCertificateAuthorities"
    ]
  }

  statement {
    sid    = "AllowServiceDiscovery"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:servicediscovery:${local.region}:${data.aws_caller_identity.current.account_id}:namespace/*",
      "arn:${data.aws_partition.current.partition}:servicediscovery:${local.region}:${data.aws_caller_identity.current.account_id}:service/*"
    ]
    actions = [
      "servicediscovery:CreateService",
      "servicediscovery:DeleteService",
      "servicediscovery:GetService",
      "servicediscovery:GetInstance",
      "servicediscovery:RegisterInstance",
      "servicediscovery:DeregisterInstance",
      "servicediscovery:ListInstances",
      "servicediscovery:ListNamespaces",
      "servicediscovery:ListServices",
      "servicediscovery:GetInstancesHealthStatus",
      "servicediscovery:UpdateInstanceCustomHealthStatus",
      "servicediscovery:GetOperation"
    ]
  }

  statement {
    sid    = "AllowRoute53"
    effect = "Allow"
    resources = [
    "arn:${data.aws_partition.current.partition}:route53:::*"]
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:GetHealthCheck",
      "route53:CreateHealthCheck",
      "route53:UpdateHealthCheck",
      "route53:DeleteHealthCheck"
    ]
  }
}


locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)


  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# Cluster
################################################################################

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.10"

  cluster_name                   = local.name
  cluster_version                = "1.24"
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 2
    }
  }

  tags = local.tags
}

################################################################################
# Kubernetes Addons
################################################################################

module "eks_blueprints_kubernetes_addons" {
  # Users should pin the version to the latest available release
  # tflint-ignore: terraform_module_pinned_source
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider     = module.eks.cluster_oidc_issuer_url
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = {
    coredns = {}
    vpc-cni = {
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
    }
    kube-proxy = {}
  }



  aws_privateca_acmca_arn     = aws_acmpca_certificate_authority.this.arn
  enable_cert_manager         = true
  enable_aws_privateca_issuer = true

  tags = local.tags
}

################################################################################
# AppMesh Addons
################################################################################

module "appmesh_addon" {
  # Users should pin the version to the latest available release
  # tflint-ignore: terraform_module_pinned_source
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons//modules/eks-blueprints-addon"

  chart            = "appmesh-controller"
  chart_version    = "1.7.0"
  repository       = "https://aws.github.io/eks-charts"
  description      = "AWS App Mesh Helm Chart"
  namespace        = "appmesh-system"
  create_namespace = true

  set = [
    {
      name  = "serviceAccount.name"
      value = "appmesh-controller"
    }
  ]

  set_irsa_name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"

  # IAM role for service account (IRSA)
  create_role = true
  role_name   = "${module.eks.cluster_name}-appmesh-controller-"
  role_policy_arns = {
    appmesh = aws_iam_policy.this.arn
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      service_account = "appmesh-controller"
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Certificate Resources
#---------------------------------------------------------------

resource "aws_acmpca_certificate_authority" "this" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name = var.eks_cluster_domain
    }
  }
}

resource "aws_acmpca_certificate" "this" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.this.arn
  certificate_signing_request = aws_acmpca_certificate_authority.this.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "this" {
  certificate_authority_arn = aws_acmpca_certificate_authority.this.arn

  certificate       = aws_acmpca_certificate.this.certificate
  certificate_chain = aws_acmpca_certificate.this.certificate_chain
}

#  This resource creates a CRD of AWSPCAClusterIssuer Kind, which then represents the ACM PCA in K8
resource "kubectl_manifest" "cluster_pca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "awspca.cert-manager.io/v1beta1"
    kind       = "AWSPCAClusterIssuer"

    metadata = {
      name = module.eks.cluster_name
    }

    spec = {
      arn = aws_acmpca_certificate_authority.this.arn
      region : local.region
    }
  })
}

# This resource creates a CRD of Certificate Kind, which then represents certificate issued from ACM PCA,
# mounted as K8 secret
resource "kubectl_manifest" "pca_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = var.certificate_name
      namespace = "default"
    }

    spec = {
      commonName = var.certificate_dns
      duration   = "2160h0m0s"
      issuerRef = {
        group = "awspca.cert-manager.io"
        kind  = "AWSPCAClusterIssuer"
        name : module.eks.cluster_name
      }
      renewBefore = "360h0m0s"
      # This is the name with which the K8 Secret will be available
      secretName = "${var.certificate_name}-clusterissuer"
      usages = [
        "server auth",
        "client auth"
      ]
      privateKey = {
        algorithm : "RSA"
        size : 2048
      }
    }
  })

  depends_on = [
    kubectl_manifest.cluster_pca_issuer,
  ]
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

resource "aws_iam_policy" "this" {
  name_prefix = "${module.eks.cluster_name}-appmesh-"
  description = "IAM Policy for App Mesh"
  policy      = data.aws_iam_policy_document.this.json
}

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.14"

  role_name_prefix = "${module.eks.cluster_name}-vpc-cni-"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

data "aws_ami" "eks-worker" {
  filter {
    name = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.first-cluster.version}-v*"]
  }
  most_recent = true
  owners = ["602401143452"]
}

data "aws_region" "current" {}

locals {
  demo-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint ${aws_eks_cluster.first-cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.first-cluster.certificate_authority.0.data}' '${var.eks-name}'
USERDATA
}

resource "aws_launch_configuration" "demo" {
  associate_public_ip_address = true
  iam_instance_profile = aws_iam_instance_profile.node-profile.name
  image_id = data.aws_ami.eks-worker.id
  instance_type = "t2.micro"
  name_prefix = "terraform-eks-demo"
  security_groups = [aws_security_group.node-sg.id]
  user_data_base64 = "${base64encode(local.demo-node-userdata)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "demo" {
  desired_capacity = 1
  launch_configuration = aws_launch_configuration.demo.id
  max_size = 2
  min_size = 1
  name = "terraform-eks-demo"
  vpc_zone_identifier = [aws_subnet.private_subnet[0].id, aws_subnet.public_subnet[0].id]

  tag {
    key = "Name"
    value = "terraform-eks-demo"
    propagate_at_launch = true
  }
  tag {
    key = "kubernetes.io/cluster/${var.eks-name}"
    value = "owned"
    propagate_at_launch = true
  }
}

locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH

apiVersion: v1
kind: ConfigMap
medadata:
  name: aws-auth
  namespace: kube-system 
data: 
  mapRoles: |
    - rolearn: ${aws_iam_role.nodes.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups: 
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH
}

output "config_map_aws_auth" {
    value = "${local.config_map_aws_auth}"
}
# Data Models and Structures

## Configuration Data Models

### Component Version Matrix
```yaml
# Structure from COMPONENT_VERSIONS.md
components:
  kubernetes:
    - version: "1.35.4"
      eks_release: "eks-1-35-9"
    - version: "1.36.0"  
      eks_release: "eks-1-36-2"
  
  core_components:
    etcd: "v3.5.21"
    coredns: "v1.14.2"
    metrics_server: "v0.7.2"
    
  authentication:
    aws_iam_authenticator: 
      - "v0.7.13"  # for K8s 1.35
      - "v0.7.15"  # for K8s 1.36
```

### Infrastructure Configuration
```java
// CDK Stack parameters
public class EksDXpressInfrastructureStack {
    private String clusterName;
    private String region; 
    private String instanceType;
    private String keyPairName;
}
```

## AMI Builder Data Models

### Packer Configuration Structure
```hcl
# eks-d-xpress.pkr.hcl structure
source "amazon-ebs" "eks-d-xpress" {
  ami_name      = "eks-d-xpress-${local.timestamp}"
  instance_type = var.instance_type
  region        = var.region
  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name               = "ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"
      root-device-type   = "ebs"
    }
  }
}

build {
  sources = ["source.amazon-ebs.eks-d-xpress"]
  
  provisioner "shell" {
    scripts = [
      "scripts/00-configure-containerd.sh",
      "scripts/01-install-base.sh",
      # ... additional scripts
    ]
  }
}
```

### Installation Script Parameters
```bash
# Environment variables used across installation scripts
export CLUSTER_NAME=""
export AWS_REGION=""
export KUBERNETES_VERSION=""
export EKS_D_RELEASE_BRANCH=""
export NODE_INSTANCE_PROFILE=""
```

## Kubernetes Resource Models

### Karpenter NodePool Structure
```yaml
apiVersion: karpenter.sh/v1alpha5
kind: NodePool
metadata:
  name: default
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
    - key: node.kubernetes.io/instance-type
      operator: In
      values: ["m5.large", "m5.xlarge", "c5.large"]
```

### Pod Identity Configuration
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-service-account
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/my-role
```

## Progress Tracking Models

### Installation Progress Structure
```bash
# progress.sh data model
PROGRESS_STAGES=(
  "infrastructure"
  "ami_build"
  "etcd_setup"
  "iam_auth"
  "eks_d_core"
  "networking"
  "storage"
  "monitoring"
  "autoscaling"
)

# Progress state
CURRENT_STAGE=""
STAGE_STATUS=""  # "running" | "completed" | "failed"
ERROR_MESSAGE=""
```

## CDK Data Models

### IAM Stack Structure
```java
// EksDXpressPackerIamStack.java
public class EksDXpressPackerIamStack {
    private Role packerRole;
    private Role eksNodeRole;
    private Role karpenterRole;
    
    // Policies
    private ManagedPolicy ec2Policy;
    private ManagedPolicy s3Policy;
    private ManagedPolicy iamPolicy;
}
```

## Component Version Tracking

### Version Compatibility Matrix
```mermaid
graph TB
    subgraph "EKS-D Releases"
        A[eks-1-35-9]
        B[eks-1-36-2]
    end
    
    subgraph "Component Versions"
        C[Kubernetes 1.35.4]
        D[Kubernetes 1.36.0]
        E[etcd 3.5.21]
        F[CNI Plugins 1.7.1]
    end
    
    A --> C
    A --> E
    A --> F
    B --> D
    B --> E
    B --> F
```

## Configuration State Models

### Cluster State Tracking
```json
{
  "cluster": {
    "name": "eks-d-xpress-cluster",
    "version": "1.35.4",
    "status": "running",
    "components": {
      "etcd": {"version": "3.5.21", "status": "healthy"},
      "apiserver": {"version": "1.35.4", "status": "ready"},
      "karpenter": {"version": "latest", "status": "active"}
    }
  }
}
```

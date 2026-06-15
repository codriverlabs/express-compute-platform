# System Architecture

## High-Level Architecture

```mermaid
graph TB
    subgraph "Development/Build Phase"
        A[Infrastructure Code] --> B[CDK Deploy]
        C[AMI Builder] --> D[Packer Build]
        E[CDK IAM Stack] --> F[Deploy IAM Resources]
    end
    
    subgraph "Runtime Deployment"
        B --> G[AWS Control Plane]
        D --> H[Golden AMIs]
        F --> I[IAM Roles/Policies]
        G --> J[EKS-D Installation]
        H --> J
        I --> J
        J --> K[Kubernetes Cluster]
    end
    
    subgraph "Cluster Components"
        K --> L[Karpenter]
        K --> M[AWS VPC CNI]
        K --> N[EBS CSI Driver]
        K --> O[CloudWatch Agent]
        K --> P[Metrics Server]
    end
```

## Deployment Pattern

The system uses a sequential, numbered installation approach:

```mermaid
sequenceDiagram
    participant U as User
    participant C as CDK
    participant P as Packer
    participant I as Installer
    participant K as Kubernetes
    
    U->>C: cdk deploy
    C->>U: Infrastructure ready
    U->>P: Build golden AMI
    P->>U: AMI ready
    U->>I: Run setup-eks-d.sh
    I->>K: Install components 05-17
    K->>U: Cluster ready (< 3 min)
```

## Component Layers

```mermaid
graph LR
    subgraph "Infrastructure Layer"
        A1[EC2 Instances]
        A2[VPC/Networking]
        A3[Security Groups]
        A4[IAM Roles]
    end
    
    subgraph "Platform Layer"
        B1[EKS-D Control Plane]
        B2[etcd]
        B3[containerd]
        B4[CNI Plugins]
    end
    
    subgraph "Service Layer"
        C1[Karpenter]
        C2[AWS Load Balancer Controller]
        C3[EBS CSI Driver]
        C4[CloudWatch Agent]
    end
    
    A1 --> B1
    A2 --> B4
    A3 --> B1
    A4 --> C1
    B1 --> C1
    B3 --> C2
    B4 --> C3
```

## Security Architecture

The system implements defense-in-depth security:
- **IAM**: Pod Identity and IRSA for workload authentication
- **Network**: VPC isolation with security groups
- **Authentication**: AWS IAM Authenticator integration
- **Authorization**: Kubernetes RBAC
- **Secrets**: CSR approval automation for certificate management

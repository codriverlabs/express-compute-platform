# Interfaces and Integration Points

## External APIs and Integrations

### AWS Service Integrations

```mermaid
graph TB
    subgraph "EKS-D-Xpress"
        A[Control Plane]
        B[Worker Nodes]
        C[Karpenter]
    end
    
    subgraph "AWS Services"
        D[EC2 API]
        E[IAM Service]
        F[EBS API]
        G[VPC API]
        H[CloudWatch]
        I[Systems Manager]
    end
    
    A --> E
    B --> D
    C --> D
    C --> E
    B --> F
    A --> G
    A --> H
    A --> I
```

**Integration Details**:
- **EC2**: Instance provisioning, AMI management, Security Groups
- **IAM**: Pod Identity, IRSA, service authentication
- **EBS**: Persistent volume provisioning via CSI driver
- **VPC**: Network isolation and CNI integration
- **CloudWatch**: Metrics, logs, and monitoring data
- **Systems Manager**: Parameter store for configuration

### Kubernetes API Interfaces

```mermaid
sequenceDiagram
    participant K as kubectl/API
    participant C as Control Plane
    participant N as Node
    participant A as AWS API
    
    K->>C: Create Pod
    C->>N: Schedule Pod
    N->>A: Request EBS Volume
    A-->>N: Volume Attached
    N-->>C: Pod Running
    C-->>K: Status Update
```

## Component Interfaces

### AMI Builder Interface
- **Input**: Packer configuration, installation scripts
- **Output**: Signed golden AMI with pre-installed components
- **API**: Packer JSON/HCL configuration format

### EKS-D Setup Interface
- **Input**: Infrastructure parameters, component versions
- **Output**: Configured Kubernetes cluster
- **API**: Shell script execution with environment variables

### CDK Stack Interface
```java
// EksDXpressPackerIamStack.java interface
public class EksDXpressPackerIamStack extends Stack {
    public EksDXpressPackerIamStack(Construct scope, String id, StackProps props)
    // Creates IAM roles and policies for Packer and EKS-D
}
```

## Configuration Interfaces

### Component Versions Interface
The system uses pinned versions defined in `COMPONENT_VERSIONS.md`:

```mermaid
graph LR
    A[EKS-D Release] --> B[Component Matrix]
    B --> C[Installation Scripts]
    C --> D[Version Validation]
    
    subgraph "Supported Versions"
        E[Kubernetes 1.35.4]
        F[Kubernetes 1.36.0]
        G[etcd 3.5.21]
        H[CoreDNS 1.14.2]
    end
    
    B --> E
    B --> F
    B --> G
    B --> H
```

### Progress Reporting Interface
```bash
# progress.sh functions
report_ready()     # Signal component ready
update_progress()  # Update installation progress
fail()            # Handle component failure
```

### Authentication Interface
- **AWS IAM Authenticator**: Integrates AWS IAM with Kubernetes RBAC
- **Pod Identity**: Direct IAM role association for pods
- **IRSA**: IAM Roles for Service Accounts (legacy compatibility)

## Network Interfaces

### VPC CNI Integration
```mermaid
graph TB
    subgraph "Pod Network"
        A[Pod 1]
        B[Pod 2]
        C[Pod 3]
    end
    
    subgraph "VPC Network"
        D[ENI 1]
        E[ENI 2]
        F[Subnet]
    end
    
    A --> D
    B --> D
    C --> E
    D --> F
    E --> F
```

### Load Balancer Integration
- **AWS Load Balancer Controller**: Manages ALB/NLB for Kubernetes Services
- **Service Type LoadBalancer**: Direct AWS ELB integration
- **Ingress**: ALB-based ingress routing

## Storage Interfaces

### EBS CSI Driver
- **StorageClasses**: Define EBS volume types and policies
- **PersistentVolumes**: Dynamic provisioning of EBS volumes
- **Volume Snapshots**: Backup and restore capabilities

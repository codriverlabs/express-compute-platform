# Workflows and Processes

## Primary Deployment Workflow

```mermaid
flowchart TD
    A[Start Deployment] --> B[Infrastructure Setup]
    B --> C[Build Golden AMI]
    C --> D[Deploy EKS-D]
    D --> E[Configure Add-ons]
    E --> F[Cluster Ready]
    
    subgraph "Infrastructure Setup"
        B1[Configure CDK]
        B2[Deploy AWS Resources]
        B3[Create IAM Roles]
    end
    
    subgraph "AMI Building"
        C1[Packer Build]
        C2[Install Components]
        C3[Sign AMI]
    end
    
    subgraph "EKS-D Installation"
        D1[Prepare etcd]
        D2[Install Control Plane]
        D3[Configure Networking]
        D4[Join Nodes]
    end
    
    subgraph "Add-on Configuration"
        E1[Install Karpenter]
        E2[Setup Monitoring]
        E3[Configure Storage]
    end
    
    B --> B1
    B1 --> B2
    B2 --> B3
    B3 --> C
    
    C --> C1
    C1 --> C2
    C2 --> C3
    C3 --> D
    
    D --> D1
    D1 --> D2
    D2 --> D3
    D3 --> D4
    D4 --> E
    
    E --> E1
    E1 --> E2
    E2 --> E3
    E3 --> F
```

## Sequential Installation Process

The EKS-D installation follows a strict sequence to ensure dependencies are met:

```mermaid
sequenceDiagram
    participant U as User
    participant S as setup-eks-d.sh
    participant E as etcd
    participant K as Kubernetes
    participant A as Add-ons
    
    U->>S: Execute installation
    S->>E: 05-prepare-etcd.sh
    E-->>S: etcd ready
    
    S->>K: 06-install-aws-iam-authenticator.sh
    K-->>S: Auth ready
    
    S->>K: 07-install-eks-d.sh
    K-->>S: Control plane ready
    
    S->>K: 08-install-cni.sh
    K-->>S: Networking ready
    
    S->>K: 09-install-cloud-provider.sh
    K-->>S: Cloud integration ready
    
    S->>K: 10-configure-node.sh
    K-->>S: Node ready
    
    S->>A: 11-install-cert-manager.sh
    A-->>S: Certificate management ready
    
    S->>A: 12-install-ecp-workload-identity.sh
    A-->>S: Pod identity ready
    
    S->>A: 13-install-ebs-csi.sh
    A-->>S: Storage ready
    
    S->>A: 14-install-metrics-server.sh
    A-->>S: Metrics ready
    
    S->>A: 15-install-karpenter.sh
    A-->>S: Autoscaling ready
    
    S->>A: 16-install-cloudwatch.sh
    A-->>S: Monitoring ready
    
    S-->>U: Cluster ready (< 3 min)
```

## AMI Building Workflow

```mermaid
flowchart LR
    A[Base Ubuntu 22.04] --> B[Configure containerd]
    B --> C[Install Base Packages]
    C --> D[Install Docker]
    D --> E[Install Helm]
    E --> F[Discover EKS-D Components]
    F --> G[Extract Container Images]
    G --> H[Pre-pull Images]
    H --> I[Sign AMI]
    I --> J[Golden AMI Ready]
    
    subgraph "Validation"
        K[Verify AMI]
        L[Test Boot]
        M[Validate Components]
    end
    
    J --> K
    K --> L
    L --> M
```

## Error Handling and Recovery

```mermaid
flowchart TD
    A[Installation Step] --> B{Success?}
    B -->|Yes| C[Next Step]
    B -->|No| D[Log Error]
    D --> E[Check Dependencies]
    E --> F{Recoverable?}
    F -->|Yes| G[Retry Step]
    F -->|No| H[Fail Installation]
    G --> B
    H --> I[Reset Cluster]
    
    subgraph "Recovery Actions"
        J[Check Network]
        K[Verify IAM Permissions]
        L[Validate Resources]
        M[Check Component Status]
    end
    
    E --> J
    E --> K
    E --> L
    E --> M
```

## Node Provisioning Workflow

```mermaid
sequenceDiagram
    participant P as Pod
    participant S as Scheduler
    participant K as Karpenter
    participant E as EC2
    participant N as Node
    
    P->>S: Schedule Pod
    S->>S: No available nodes
    S->>K: Trigger provisioning
    K->>E: Launch instance
    E-->>K: Instance running
    K->>N: Bootstrap node
    N->>N: Join cluster
    N-->>K: Node ready
    K-->>S: Node available
    S->>N: Schedule Pod
    N-->>P: Pod running
```

## Monitoring and Observability Workflow

```mermaid
graph TB
    subgraph "Data Collection"
        A[Kubelet Metrics]
        B[Container Logs]
        C[System Metrics]
        D[Application Metrics]
    end
    
    subgraph "Processing"
        E[Metrics Server]
        F[CloudWatch Agent]
        G[Prometheus]
    end
    
    subgraph "Storage & Visualization"
        H[CloudWatch Metrics]
        I[CloudWatch Logs]
        J[Grafana Dashboards]
    end
    
    A --> E
    B --> F
    C --> F
    D --> G
    
    E --> H
    F --> I
    G --> H
    
    H --> J
    I --> J
```

## Cleanup and Reset Workflow

```mermaid
flowchart TD
    A[Reset Request] --> B[Stop Kubernetes]
    B --> C[Clean etcd Data]
    C --> D[Remove CNI Config]
    D --> E[Clean Container Runtime]
    E --> F[Remove Certificates]
    F --> G[Reset Network]
    G --> H[Clean Logs]
    H --> I[System Ready for Reinstall]
    
    subgraph "Safety Checks"
        J[Backup Important Data]
        K[Confirm Reset]
        L[Validate Cleanup]
    end
    
    A --> J
    J --> K
    K --> B
    I --> L
```

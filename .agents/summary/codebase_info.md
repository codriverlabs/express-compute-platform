# EKS-D-Xpress Codebase Information

## Overview
EKS-D-Xpress is an EKS-compatible distribution system designed to deploy Kubernetes clusters with Karpenter support in under 3 minutes. The system combines infrastructure automation (AWS CDK), custom AMI building, and streamlined EKS-D installation.

## Repository Statistics
- **Total Files**: 893
- **Lines of Code**: 2,918
- **Primary Languages**: Shell scripts (889 files), Java (4 files)
- **Size Category**: Large (L)

## Technology Stack
- **Infrastructure**: AWS CDK (Java) for AWS resource provisioning
- **AMI Building**: Packer with HashiCorp configuration
- **Deployment**: Java CDK for both IAM and infrastructure management
- **Installation**: Shell script automation
- **Container Runtime**: containerd
- **Kubernetes Distribution**: EKS-D (AWS Kubernetes distro)

## Architecture Pattern
The codebase follows a multi-phase deployment pattern:
1. Infrastructure provisioning (AWS CDK)
2. Golden AMI creation (Packer + scripts)
3. EKS-D installation (numbered shell scripts)
4. Add-on deployment (Karpenter, CNI, CSI, monitoring)

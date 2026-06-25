# EKS-DX Control Plane - CDK Deployment

## Quick Deploy (no build required)

    cd eks-d-xpress-control-plane-<version>
    cdk deploy --app cdk.out EksDXpressControlPlaneStack

No Java, no Maven needed - the stack is pre-synthesized.

## Custom Deploy (with modifications)

    cd infra
    cdk deploy EksDXpressControlPlaneStack --context jvmTenant=true

Pre-built Lambda zips are in assets/ - no need to rebuild Lambda code.

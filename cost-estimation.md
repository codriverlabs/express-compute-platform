# Express Compute Cost Estimation

## Monthly Cost Breakdown (per team member)

### Control Plane (Always Running)
| Component | Instance Type | Hours/Month | On-Demand Price | With Savings Plan | Monthly Cost |
|-----------|---------------|-------------|-----------------|-------------------|--------------|
| Control Plane (default) | c6g.xlarge | 744 | $0.136/hr | $0.097/hr (29% off) | ~$72 |

> The default control plane instance is `c6g.xlarge` (4 vCPU / 8 GiB, Graviton2 compute-optimized).
> Override with `--instance-type-arm64` in `deploy.sh` if needed.

### Savings Plan Options (c6g.xlarge, us-east-1)

| Plan Type | Term | Payment | Hourly Rate | Monthly (744h) | Discount |
|-----------|------|---------|-------------|-----------------|----------|
| On-Demand | — | — | $0.136 | $101 | — |
| Compute Savings Plan | 1yr | No upfront | $0.097 | $72 | 29% |
| **EC2 Instance Savings Plan** | **1yr** | **No upfront** | **$0.082** | **$61** | **40%** |
| EC2 Instance Savings Plan | 1yr | All upfront | $0.078 | $58 | 43% |
| EC2 Instance Savings Plan | 3yr | No upfront | $0.062 | $46 | 54% |

> **EC2 Instance Savings Plans** offer the deepest discounts when you commit to a specific
> instance family (c6g) in a specific region. Ideal for teams that have standardized on
> Express Compute with Graviton in a single region. Unlike Compute Savings Plans, they do
> not cover other instance families or regions.

### Storage (Always Running)
| Component | Size | Type | Monthly Cost |
|-----------|------|------|--------------|
| Root Volume | 50 GB | gp3 | ~$4.00 |
| etcd Volume | 20 GB | gp3 | ~$1.60 |
| **Total Storage** | | | **~$5.60** |

### Worker Nodes (Spot - Pay Only When Running)
| Workload | Instance Type | Spot Price | Hours Used | Monthly Cost |
|----------|---------------|------------|------------|--------------|
| Development | t3.medium | ~$0.0125/hr | 40 hrs | ~$0.50 |
| Testing | m5.large | ~$0.0288/hr | 80 hrs | ~$2.30 |
| Load Testing | c5.xlarge | ~$0.0510/hr | 20 hrs | ~$1.02 |

### Networking
| Component | Monthly Cost |
|-----------|--------------|
| NAT Gateway | ~$32.40 |
| Data Transfer | ~$2-5 |
| **Total Networking** | **~$35** |

## Total Monthly Cost Estimates

### Realistic Usage Scenarios (c6g.xlarge)

#### Scenario 1: Full Development Workday (8 hours/day)
| Pricing Model | Control Plane | Storage | Networking | Workers | **Total** |
|---------------|--------------|---------|------------|---------|-----------|
| On-Demand | 176h × $0.136 = $23.94 | $5.60 | $35 | $10-25 | **$75-90** |
| Compute SP | 176h × $0.097 = $17.07 | $5.60 | $35 | $10-25 | **$68-83** |
| **EC2 Instance SP (1yr)** | 176h × $0.082 = $14.43 | $5.60 | $35 | $10-25 | **$65-80** |
| EC2 Instance SP (3yr) | 176h × $0.062 = $10.91 | $5.60 | $35 | $10-25 | **$62-77** |

#### Scenario 2: Business Hours Only (9-5, weekdays)
| Pricing Model | Control Plane | Storage | Networking | Workers | **Total** |
|---------------|--------------|---------|------------|---------|-----------|
| Compute SP | 160h × $0.097 = $15.52 | $5.60 | $35 | $5-15 | **$61-71** |
| **EC2 Instance SP (1yr)** | 160h × $0.082 = $13.12 | $5.60 | $35 | $5-15 | **$59-69** |
| EC2 Instance SP (3yr) | 160h × $0.062 = $9.92 | $5.60 | $35 | $5-15 | **$55-65** |

#### Scenario 3: Spot + Hibernation (Ultimate Savings)
- **Control Plane**: Spot pricing (~65% off) + hibernation
- **Estimated**: 160 hrs/month × $0.048/hr = $7.68
- **Storage**: $5.60
- **Networking**: $35.00 (shared)
- **Worker Nodes**: $5-15 (Spot)
- **Total**: **$53-63/month per developer**

> Spot cannot be combined with Savings Plans. Use Spot for maximum discount where
> occasional interruption (with hibernation) is acceptable.

## Cost Optimization Strategies

### 1. Hibernation & Scheduling (Major Savings)
```bash
# Control plane usage patterns (c6g.xlarge, EC2 Instance SP 1yr)
Full-time (744 hrs/month): $61/month
8 hours/day (176 hrs/month): $14.43/month (86% savings vs full-time on-demand)
Business hours only (160 hrs/month): $13.12/month (87% savings)
```

> EC2 Instance Savings Plans apply per-hour-of-use — you only pay the SP rate for hours
> the instance is running. Combining scheduling (stop/start) with EC2 Instance SP is the
> optimal strategy for dev workstations.

**Implementation Options:**
- **Manual**: Stop/start instances via AWS Console or CLI
- **Scheduled**: CloudWatch Events + Lambda for auto start/stop
- **Hibernation**: EBS-backed hibernation for instant resume
- **Spot + Hibernation**: Additional 60-70% savings on compute

### 2. Savings Plans

Two options depending on flexibility needs:

```bash
# Compute Savings Plan (flexible — covers any instance family, region, OS)
c6g.xlarge: $0.136/hr → $0.097/hr (29% savings)
# Good if you might switch instance types or regions later

# EC2 Instance Savings Plan (locked to c6g in one region — deeper discount)
c6g.xlarge: $0.136/hr → $0.082/hr (40% savings, 1yr no upfront)
c6g.xlarge: $0.136/hr → $0.062/hr (54% savings, 3yr no upfront)
# Best for teams committed to c6g.xlarge in a specific region
```

**Choosing between them:**
| Factor | Compute SP | EC2 Instance SP |
|--------|-----------|-----------------|
| Discount | 29% | 40-54% |
| Flexibility | Any instance, any region | One family + one region |
| Risk | Low (portable) | Medium (locked in) |
| Best for | Experimentation, multi-region | Production teams, stable config |

> EC2 Instance Savings Plans still cover *any size* within the family — a c6g.xlarge
> commitment also covers c6g.medium, c6g.2xlarge, etc. if you resize later.

### 3. Spot Instance Savings
```bash
# Typical spot discounts (worker nodes)
c6g.xlarge:  $0.136 → $0.048 (65% savings)
m6g.large:   $0.077 → $0.025 (68% savings)
c5.xlarge:   $0.170 → $0.051 (70% savings)
```

### 4. Shared Infrastructure
- **Shared NAT Gateway**: Split $32.40 across team members
- **Shared VPC**: Reduce networking costs per person
- **Resource Tagging**: Track individual usage

### 5. Auto-Scaling Configuration
```yaml
# Aggressive scale-down for cost savings
disruption:
  consolidateAfter: 30s    # Quick consolidation
  expireAfter: 2160h       # 90-day max lifetime

limits:
  cpu: 100                 # Limit max resources
  memory: 100Gi
```

## Team Cost Scenarios

### 5-Person Team (8-hour workdays)
| Scenario | Pricing Model | Individual Cost | Team Total | Annual Cost |
|----------|--------------|----------------|------------|-------------|
| Business Hours | Compute SP | $68/month | $340/month | $4,080/year |
| Business Hours | EC2 Instance SP (1yr) | $65/month | $325/month | $3,900/year |
| Business Hours | EC2 Instance SP (3yr) | $62/month | $310/month | $3,720/year |
| Spot + Hibernation | Spot | $58/month | $290/month | $3,480/year |

### 10-Person Team (8-hour workdays)
| Scenario | Pricing Model | Individual Cost | Team Total | Annual Cost |
|----------|--------------|----------------|------------|-------------|
| Business Hours | Compute SP | $68/month | $680/month | $8,160/year |
| Business Hours | EC2 Instance SP (1yr) | $65/month | $650/month | $7,800/year |
| Business Hours | EC2 Instance SP (3yr) | $62/month | $620/month | $7,440/year |
| Spot + Hibernation | Spot | $58/month | $580/month | $6,960/year |

> For a 10-person team on EC2 Instance SP (1yr) vs. on-demand always-on: **$4,560/year saved**.

## Comparison with Alternatives

### vs. Managed EKS
| Component | EKS-D (EC2 Instance SP 1yr) | Managed EKS | Savings |
|-----------|-------------------|-------------|---------|
| Control Plane | $61/month (c6g.xlarge) | $73/month | **16% cheaper** |
| Worker Nodes | Same (Spot) | Same (Spot) | $0 |
| **Total** | | | **$144/year saved per cluster + isolation benefits** |

### Key Advantages Over Managed EKS
- **Isolation**: Dedicated cluster per team member — no resource contention
- **Full Karpenter**: Complete Karpenter v1 integration with NodePools
- **No API Limits**: No EKS API server throttling
- **Complete Control**: Customize control plane, etcd, scheduler settings
- **Performance**: c6g.xlarge (4 vCPU / 8 GiB) handles cert-manager, KEDA, operators smoothly
- **Use Case 1 - CI/CD**: Instant isolated clusters per PR/branch for integration testing
- **Use Case 2 - Development**: Safe environment for CRD/operator development without affecting shared clusters
- **Use Case 3 - Complex Workloads**: Run cert-manager, KEDA, Istio, ArgoCD without resource conflicts

### Additional Benefits with c6g.xlarge
- **Cert-Manager**: Handles certificate lifecycle without CPU throttling
- **KEDA**: Smooth autoscaling decisions with adequate resources
- **Operators**: Multiple operators (Prometheus, Grafana, ArgoCD) run efficiently
- **Development Velocity**: No waiting for shared cluster resources
- **Debugging**: Direct etcd access for troubleshooting complex issues

### When Managed EKS Makes Sense
- Need cross-team shared cluster
- Want AWS-managed upgrades
- Prefer less operational overhead

### When EKS-D Makes Sense
- Individual team environments needed
- Cost optimization priority
- Learning Kubernetes internals
- CI/CD pipeline testing
- CRD/operator development

### vs. Local Development
| Component | EKS-D | Local (Docker Desktop) | Trade-offs |
|-----------|-------|----------------------|------------|
| Cost | $58-65/month | $0 | Cloud integration vs. free |
| AWS Integration | Full | Limited | Native vs. simulated |
| Scalability | Unlimited | Limited by laptop | Real vs. constrained |

## Budget Planning

### Monthly Budget per Team Member (Realistic Usage)

| Pricing Model | Business Hours | Full-Time (always-on) |
|---------------|---------------|-----------------------|
| On-Demand | $90/month | $142/month |
| Compute SP (1yr) | $68/month | $113/month |
| EC2 Instance SP (1yr) | $65/month | $102/month |
| EC2 Instance SP (3yr) | $62/month | $87/month |
| Spot + Hibernation | $58/month | N/A |

### Annual Budget (10-person team)

| Pricing Model | Business Hours | Full-Time |
|---------------|---------------|-----------|
| Compute SP | $8,160/year | $13,560/year |
| EC2 Instance SP (1yr) | $7,800/year | $12,240/year |
| EC2 Instance SP (3yr) | $7,440/year | $10,440/year |

## Cost Monitoring

### CloudWatch Billing Alerts
```bash
# Set up billing alerts for each team member
aws cloudwatch put-metric-alarm \
  --alarm-name "EKS-D-Monthly-Cost-Alert" \
  --alarm-description "Alert when monthly cost exceeds $100" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold
```

### Cost Allocation Tags
```bash
# Tag EC2 instances for cost tracking
aws ec2 create-tags --resources <instance-id> --tags \
  Key=Team,Value=ECP \
  Key=Owner,Value=<team-member> \
  Key=Environment,Value=development \
  Key=Project,Value=eks-d-cluster
```

## Use Cases

### 1. Instant EKS Cluster for CI/CD
- Spin up isolated EKS-D clusters per PR/branch for integration testing
- Each developer gets dedicated test environment without waiting for shared cluster
- Parallel test execution - no queueing or resource contention
- Teardown when done - pay only for actual test runtime

### 2. EKS Development (CRD/Operator Development)
- Deploy and test cluster-wide resources (CRDs, webhooks, operators)
- No pollution of shared development clusters
- Safe experimentation with admission controllers, API servers
- Direct access to control plane for debugging etcd, scheduler, controller-manager

## ROI Analysis

### Development Velocity
- **Setup Time**: 2-3 hours vs. days for manual setup
- **Consistency**: Identical environments across team
- **AWS Integration**: Native vs. simulated locally

### Learning Value
- **Kubernetes Operations**: Real cluster management
- **AWS Services**: Hands-on experience with EC2, VPC, IAM
- **Cost Optimization**: Spot instances, Savings Plans

### Production Readiness
- **Skills Transfer**: Direct application to production
- **Architecture Patterns**: Scalable, cloud-native designs
- **Operational Experience**: Monitoring, troubleshooting, scaling

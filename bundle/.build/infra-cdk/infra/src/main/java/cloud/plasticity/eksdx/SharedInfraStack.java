package cloud.plasticity.eksdx;

import software.amazon.awscdk.CfnTag;
import software.amazon.awscdk.Fn;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.services.ec2.CfnEIP;
import software.amazon.awscdk.services.ec2.CfnFlowLog;
import software.amazon.awscdk.services.ec2.CfnInternetGateway;
import software.amazon.awscdk.services.ec2.CfnLaunchTemplate;
import software.amazon.awscdk.services.ec2.CfnNatGateway;
import software.amazon.awscdk.services.ec2.CfnRoute;
import software.amazon.awscdk.services.ec2.CfnRouteTable;
import software.amazon.awscdk.services.ec2.CfnSubnet;
import software.amazon.awscdk.services.ec2.CfnSubnetRouteTableAssociation;
import software.amazon.awscdk.services.ec2.CfnVPC;
import software.amazon.awscdk.services.ec2.CfnVPCEndpoint;
import software.amazon.awscdk.services.ec2.CfnVPCGatewayAttachment;
import software.amazon.awscdk.services.ecr.CfnPullThroughCacheRule;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.services.logs.RetentionDays;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.constructs.Construct;

import java.util.List;

public class SharedInfraStack extends Stack {

    private final String projectName;
    private final String instanceTypeArm64;
    private final String instanceTypeX86_64;
    private final int diskSizeGb;

    public SharedInfraStack(Construct scope, String id, StackProps props) {
        super(scope, id, props);

        this.projectName = (String) this.getNode().tryGetContext("projectName");
        this.instanceTypeArm64 = (String) this.getNode().tryGetContext("instanceTypeArm64");
        this.instanceTypeX86_64 = (String) this.getNode().tryGetContext("instanceTypeX86_64");
        this.diskSizeGb = (int) this.getNode().tryGetContext("diskSizeGb");

        boolean enableNatGateway = Boolean.TRUE.equals(this.getNode().tryGetContext("enableNatGateway"));

        var networking = createNetworking(enableNatGateway);
        createFlowLogs(networking.vpcId());
        createEcrPullThroughCache();
        createS3Endpoint(networking.vpcId(), networking.publicRtId(), networking.privateRtId());
        createLaunchTemplates();
        createNetworkSsmParams(networking, enableNatGateway);
    }

    // ── Networking ────────────────────────────────────────────────────────────

    private record Networking(String vpcId, String publicRtId, String privateRtId) {}

    private Networking createNetworking(boolean enableNatGateway) {
        CfnVPC vpc = CfnVPC.Builder.create(this, "Vpc")
                .cidrBlock("10.0.0.0/16")
                .enableDnsHostnames(true)
                .enableDnsSupport(true)
                .tags(List.of(
                        tag("Name", projectName + "-shared-vpc"),
                        tag("Project", projectName),
                        tag("ManagedBy", "CDK")))
                .build();

        CfnInternetGateway igw = CfnInternetGateway.Builder.create(this, "Igw")
                .tags(List.of(
                        tag("Name", projectName + "-igw"),
                        tag("Project", projectName)))
                .build();

        CfnVPCGatewayAttachment.Builder.create(this, "IgwAttachment")
                .vpcId(vpc.getRef())
                .internetGatewayId(igw.getRef())
                .build();

        String az = Fn.select(0, Fn.getAzs(this.getRegion()));

        CfnSubnet natSubnet = CfnSubnet.Builder.create(this, "NatSubnet")
                .vpcId(vpc.getRef())
                .cidrBlock("10.0.0.0/24")
                .availabilityZone(az)
                .mapPublicIpOnLaunch(true)
                .tags(List.of(
                        tag("Name", projectName + "-nat-subnet"),
                        tag("Project", projectName),
                        tag("Type", "NAT")))
                .build();

        CfnEIP natEip = null;
        CfnNatGateway natGw = null;

        if (enableNatGateway) {
            natEip = CfnEIP.Builder.create(this, "NatEip")
                    .domain("vpc")
                    .tags(List.of(
                            tag("Name", projectName + "-nat-eip"),
                            tag("Project", projectName)))
                    .build();
            natEip.addDependency(igw);

            natGw = CfnNatGateway.Builder.create(this, "NatGateway")
                    .allocationId(natEip.getAttrAllocationId())
                    .subnetId(natSubnet.getRef())
                    .tags(List.of(
                            tag("Name", projectName + "-nat-gw"),
                            tag("Project", projectName)))
                    .build();
        }

        // Public route table
        CfnRouteTable publicRt = CfnRouteTable.Builder.create(this, "PublicRt")
                .vpcId(vpc.getRef())
                .tags(List.of(
                        tag("Name", projectName + "-public-rt"),
                        tag("Project", projectName)))
                .build();

        CfnRoute.Builder.create(this, "PublicDefaultRoute")
                .routeTableId(publicRt.getRef())
                .destinationCidrBlock("0.0.0.0/0")
                .gatewayId(igw.getRef())
                .build();

        CfnSubnetRouteTableAssociation.Builder.create(this, "NatSubnetRtAssoc")
                .subnetId(natSubnet.getRef())
                .routeTableId(publicRt.getRef())
                .build();

        // Private route table — NAT route only if NAT GW exists
        CfnRouteTable privateRt = CfnRouteTable.Builder.create(this, "PrivateRt")
                .vpcId(vpc.getRef())
                .tags(List.of(
                        tag("Name", projectName + "-private-rt"),
                        tag("Project", projectName)))
                .build();

        if (enableNatGateway && natGw != null) {
            CfnRoute.Builder.create(this, "PrivateNatRoute")
                    .routeTableId(privateRt.getRef())
                    .destinationCidrBlock("0.0.0.0/0")
                    .natGatewayId(natGw.getRef())
                    .build();
        }

        return new Networking(vpc.getRef(), publicRt.getRef(), privateRt.getRef());
    }

    // ── VPC Flow Logs ─────────────────────────────────────────────────────────

    private void createFlowLogs(String vpcId) {
        String logGroupName = "/aws/vpc/" + this.getRegion() + "/" + projectName + "-flow-logs";

        LogGroup logGroup = LogGroup.Builder.create(this, "FlowLogGroup")
                .logGroupName(logGroupName)
                .retention(RetentionDays.ONE_WEEK)
                .removalPolicy(RemovalPolicy.DESTROY)
                .build();

        Role role = Role.Builder.create(this, "FlowLogsRole")
                .roleName(projectName + "-vpc-flow-logs-role")
                .assumedBy(new ServicePrincipal("vpc-flow-logs.amazonaws.com"))
                .build();

        role.addToPolicy(PolicyStatement.Builder.create()
                .actions(List.of(
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogGroups",
                        "logs:DescribeLogStreams"))
                .resources(List.of("*"))
                .build());

        CfnFlowLog.Builder.create(this, "FlowLog")
                .resourceId(vpcId)
                .resourceType("VPC")
                .trafficType("ALL")
                .logDestinationType("cloud-watch-logs")
                .logDestination(logGroup.getLogGroupArn())
                .deliverLogsPermissionArn(role.getRoleArn())
                .tags(List.of(
                        tag("Name", projectName + "-vpc-flow-log"),
                        tag("Project", projectName)))
                .build();
    }

    // ── ECR Pull-Through Cache ────────────────────────────────────────────────
    // L1 — no L2 construct exists for pull-through cache rules

    private void createEcrPullThroughCache() {
        CfnPullThroughCacheRule.Builder.create(this, "EcrPublicCache")
                .ecrRepositoryPrefix("public-ecr")
                .upstreamRegistryUrl("public.ecr.aws")
                .build();

        CfnPullThroughCacheRule.Builder.create(this, "RegistryK8sCache")
                .ecrRepositoryPrefix("registry-k8s-io")
                .upstreamRegistryUrl("registry.k8s.io")
                .build();

        // Quay is a public registry — no credentials required.
        CfnPullThroughCacheRule.Builder.create(this, "QuayCache")
                .ecrRepositoryPrefix("quay-io")
                .upstreamRegistryUrl("quay.io")
                .build();
    }

    // ── S3 Gateway Endpoint ───────────────────────────────────────────────────
    // Free — keeps ECR image pulls, EBS CSI, and Karpenter pricing off the NAT gateway

    private void createS3Endpoint(String vpcId, String publicRtId, String privateRtId) {
        CfnVPCEndpoint.Builder.create(this, "S3Endpoint")
                .vpcId(vpcId)
                .serviceName("com.amazonaws." + this.getRegion() + ".s3")
                .vpcEndpointType("Gateway")
                .routeTableIds(List.of(publicRtId, privateRtId))
                .build();
    }

    // ── Shared Launch Templates ───────────────────────────────────────────────
    // One spot (hibernation) + one on-demand per arch.
    // No imageId — AMI is passed as override at RunInstances time by the Lambda.
    // After creation, LT IDs are written to SSM for the Lambda to consume.

    private record LtConfig(String arch, boolean spot) {
        String key() { return (spot ? "spot" : "ondemand") + "-" + arch; }
        String mode() { return spot ? "spot" : "ondemand"; }
        String instanceType(String arm64Type, String x86Type) {
            return arch.equals("arm64") ? arm64Type : x86Type;
        }
    }

    private void createLaunchTemplates() {
        List<LtConfig> configs = List.of(
                new LtConfig("arm64",  true),
                new LtConfig("arm64",  false),
                new LtConfig("x86_64", true),
                new LtConfig("x86_64", false)
        );

        for (LtConfig cfg : configs) {
            String ltName = projectName + "-" + cfg.key();

            var ltDataBuilder = CfnLaunchTemplate.LaunchTemplateDataProperty.builder()
                    .instanceType(cfg.instanceType(instanceTypeArm64, instanceTypeX86_64))
                    .metadataOptions(CfnLaunchTemplate.MetadataOptionsProperty.builder()
                            .httpTokens("required")
                            .httpPutResponseHopLimit(2)
                            .build())
                    .blockDeviceMappings(List.of(
                            CfnLaunchTemplate.BlockDeviceMappingProperty.builder()
                                    .deviceName("/dev/xvda")
                                    .ebs(CfnLaunchTemplate.EbsProperty.builder()
                                            .volumeType("gp3")
                                            .volumeSize(diskSizeGb)
                                            .deleteOnTermination(true)
                                            .encrypted(true)
                                            .build())
                                    .build(),
                            CfnLaunchTemplate.BlockDeviceMappingProperty.builder()
                                    .deviceName("/dev/sdf")
                                    .ebs(CfnLaunchTemplate.EbsProperty.builder()
                                            .volumeType("gp3")
                                            .volumeSize(20)
                                            .deleteOnTermination(true)
                                            .encrypted(true)
                                            .build())
                                    .build()))
                    .tagSpecifications(List.of(
                            CfnLaunchTemplate.TagSpecificationProperty.builder()
                                    .resourceType("instance")
                                    .tags(List.of(
                                            tag("Platform", "eks-d-xpress"),
                                            tag("Arch", cfg.arch()),
                                            tag("ManagedBy", "Karpenter")))
                                    .build(),
                            CfnLaunchTemplate.TagSpecificationProperty.builder()
                                    .resourceType("volume")
                                    .tags(List.of(
                                            tag("Platform", "eks-d-xpress"),
                                            tag("ManagedBy", "CDK")))
                                    .build()));

            if (cfg.spot()) {
                ltDataBuilder
                        .instanceMarketOptions(CfnLaunchTemplate.InstanceMarketOptionsProperty.builder()
                                .marketType("spot")
                                .spotOptions(CfnLaunchTemplate.SpotOptionsProperty.builder()
                                        .instanceInterruptionBehavior("hibernate")
                                        .build())
                                .build())
                        .hibernationOptions(CfnLaunchTemplate.HibernationOptionsProperty.builder()
                                .configured(true)
                                .build());
            }

            CfnLaunchTemplate lt = CfnLaunchTemplate.Builder.create(this, "Lt-" + cfg.key())
                    .launchTemplateName(ltName)
                    .launchTemplateData(ltDataBuilder.build())
                    .tagSpecifications(List.of(
                            CfnLaunchTemplate.LaunchTemplateTagSpecificationProperty.builder()
                                    .resourceType("launch-template")
                                    .tags(List.of(
                                            tag("Name", ltName),
                                            tag("Platform", "eks-d-xpress"),
                                            tag("Arch", cfg.arch()),
                                            tag("Mode", cfg.spot() ? "spot" : "on-demand"),
                                            tag("ManagedBy", "CDK")))
                                    .build()))
                    .build();

            // Publish LT ID to SSM for Lambda consumption
            StringParameter.Builder.create(this, "SsmLt-" + cfg.key())
                    .parameterName("/eks-d-xpress/infra/launch-template/" + cfg.arch() + "/" + cfg.mode())
                    .stringValue(lt.getRef())
                    .description("EKS-DX shared launch template ID — " + cfg.key())
                    .build();
        }
    }

    // ── Network SSM Parameters ────────────────────────────────────────────────

    private void createNetworkSsmParams(Networking networking, boolean enableNatGateway) {
        StringParameter.Builder.create(this, "SsmVpcId")
                .parameterName("/eks-d-xpress/infra/network/vpc-id")
                .stringValue(networking.vpcId())
                .description("EKS-DX shared VPC ID")
                .build();

        StringParameter.Builder.create(this, "SsmNatGatewayEnabled")
                .parameterName("/eks-d-xpress/infra/network/nat-gateway-enabled")
                .stringValue(String.valueOf(enableNatGateway))
                .description("EKS-DX shared VPC — NAT gateway enabled flag")
                .build();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static CfnTag tag(String key, String value) {
        return CfnTag.builder().key(key).value(value).build();
    }
}

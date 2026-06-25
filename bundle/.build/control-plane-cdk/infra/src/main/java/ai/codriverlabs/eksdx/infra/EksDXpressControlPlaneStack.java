package ai.codriverlabs.eksdx.infra;

import software.amazon.awscdk.Aws;
import software.amazon.awscdk.CfnCondition;
import software.amazon.awscdk.CfnConditionProps;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.Fn;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.services.apigateway.AccessLogFormat;
import software.amazon.awscdk.services.apigateway.AuthorizationType;
import software.amazon.awscdk.services.apigateway.CfnBasePathMapping;
import software.amazon.awscdk.services.apigateway.CfnDomainName;
import software.amazon.awscdk.services.apigateway.LambdaIntegration;
import software.amazon.awscdk.services.apigateway.LogGroupLogDestination;
import software.amazon.awscdk.services.apigateway.MethodLoggingLevel;
import software.amazon.awscdk.services.apigateway.MethodOptions;
import software.amazon.awscdk.services.apigateway.RestApi;
import software.amazon.awscdk.services.apigateway.IResource;
import software.amazon.awscdk.services.apigateway.StageOptions;
import software.amazon.awscdk.services.cloudwatch.Alarm;
import software.amazon.awscdk.services.cloudwatch.MetricOptions;
import software.amazon.awscdk.services.cloudwatch.TreatMissingData;
import software.amazon.awscdk.services.dynamodb.Attribute;
import software.amazon.awscdk.services.dynamodb.AttributeType;
import software.amazon.awscdk.services.dynamodb.BillingMode;
import software.amazon.awscdk.services.dynamodb.PointInTimeRecoverySpecification;
import software.amazon.awscdk.services.dynamodb.Table;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.lambda.Architecture;
import software.amazon.awscdk.services.lambda.CfnFunction;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.FunctionUrl;
import software.amazon.awscdk.services.lambda.FunctionUrlAuthType;
import software.amazon.awscdk.services.lambda.FunctionUrlOptions;
import software.amazon.awscdk.services.lambda.InvokeMode;
import software.amazon.awscdk.services.lambda.LayerVersion;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.services.logs.RetentionDays;
import software.amazon.awscdk.Tags;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.amazon.awscdk.CfnParameter;
import software.amazon.awscdk.services.apigatewayv2.HttpApi;
import software.amazon.awscdk.services.apigatewayv2.HttpMethod;
import software.amazon.awscdk.services.apigatewayv2.AddRoutesOptions;
import software.amazon.awscdk.aws_apigatewayv2_authorizers.HttpIamAuthorizer;
import software.amazon.awscdk.aws_apigatewayv2_integrations.HttpLambdaIntegration;
import software.constructs.Construct;

import java.nio.file.Path;
import java.util.List;
import java.util.Map;

/**
 * CDK stack for EKS-DX — at parity with sam.yaml.
 *
 * Three Lambda functions:
 *   credentialFn  — hot path, SnapStart, JVM
 *   mgmtFn        — cluster/association CRUD, JVM
 *   tenantFn      — async provisioning + SSE stream, GraalVM native arm64, Function URL
 */
public class EksDXpressControlPlaneStack extends Stack {

    public EksDXpressControlPlaneStack(Construct scope, String id, StackProps props) {
        super(scope, id, props);

        // -----------------------------------------------------------------------
        // Stack-level tags
        // -----------------------------------------------------------------------
        Tags.of(this).add("Project", "eks-d-xpress-control-plane");

        // Resolve asset paths: release bundle uses ../assets/ by default.
        // Development builds use --context development=true to resolve from target/ dirs.
        boolean development = "true".equals(this.getNode().tryGetContext("development"));
        String credentialZip, mgmtZip, tenantZip;
        if (development) {
            String root = Path.of("eks-dx-credential-service").toFile().isDirectory() ? "" : "../";
            credentialZip = root + "eks-dx-credential-service/target/function.zip";
            mgmtZip = root + "eks-dx-mgmt-service/target/function.zip";
            tenantZip = root + "eks-dx-tenant-service/target/function.zip";
        } else {
            String root = Path.of("assets").toFile().isDirectory() ? "" : "../";
            credentialZip = root + "assets/credential-service.zip";
            mgmtZip = root + "assets/mgmt-service.zip";
            tenantZip = root + "assets/tenant-service.zip";
        }

        // -----------------------------------------------------------------------
        // Parameters
        // -----------------------------------------------------------------------
        CfnParameter domainNameParam = CfnParameter.Builder.create(this, "DomainName")
            .type("String").defaultValue("")
            .description("Custom domain name (leave empty to skip)").build();

        CfnParameter certArnParam = CfnParameter.Builder.create(this, "CertificateArn")
            .type("String").defaultValue("")
            .description("ACM certificate ARN for custom domain").build();

        CfnCondition hasCustomDomain = new CfnCondition(this, "HasCustomDomain",
            CfnConditionProps.builder()
                .expression(Fn.conditionNot(
                    Fn.conditionEquals(domainNameParam.getValueAsString(), "")))
                .build());

        // -----------------------------------------------------------------------
        // DynamoDB Tables
        // -----------------------------------------------------------------------
        Table clustersTable = Table.Builder.create(this, "ClustersTable")
            .tableName("eks-d-xpress-clusters")
            .partitionKey(Attribute.builder().name("clusterName").type(AttributeType.STRING).build())
            .billingMode(BillingMode.PAY_PER_REQUEST)
            .removalPolicy(RemovalPolicy.DESTROY)
            .pointInTimeRecoverySpecification(PointInTimeRecoverySpecification.builder().pointInTimeRecoveryEnabled(true).build())
            .build();

        Table associationsTable = Table.Builder.create(this, "AssociationsTable")
            .tableName("eks-d-xpress-associations")
            .partitionKey(Attribute.builder().name("PK").type(AttributeType.STRING).build())
            .sortKey(Attribute.builder().name("SK").type(AttributeType.STRING).build())
            .billingMode(BillingMode.PAY_PER_REQUEST)
            .removalPolicy(RemovalPolicy.DESTROY)
            .pointInTimeRecoverySpecification(PointInTimeRecoverySpecification.builder().pointInTimeRecoveryEnabled(true).build())
            .build();

        Table tenantsTable = Table.Builder.create(this, "TenantsTable")
            .tableName("eks-d-xpress-tenants")
            .partitionKey(Attribute.builder().name("tenantId").type(AttributeType.STRING).build())
            .billingMode(BillingMode.PAY_PER_REQUEST)
            .removalPolicy(RemovalPolicy.DESTROY)
            .pointInTimeRecoverySpecification(PointInTimeRecoverySpecification.builder().pointInTimeRecoveryEnabled(true).build())
            .build();

        // -----------------------------------------------------------------------
        // SSM Parameter lookups (written by eks-d-xpress/infra stack)
        // -----------------------------------------------------------------------
        String ltArm64Ondemand = StringParameter.valueForStringParameter(
            this, "/eks-d-xpress/infra/launch-template/arm64/ondemand");
        String ltArm64Spot = StringParameter.valueForStringParameter(
            this, "/eks-d-xpress/infra/launch-template/arm64/spot");
        String ltX86Ondemand = StringParameter.valueForStringParameter(
            this, "/eks-d-xpress/infra/launch-template/x86_64/ondemand");
        String ltX86Spot = StringParameter.valueForStringParameter(
            this, "/eks-d-xpress/infra/launch-template/x86_64/spot");
        String vpcId = StringParameter.valueForStringParameter(
            this, "/eks-d-xpress/infra/network/vpc-id");

        // -----------------------------------------------------------------------
        // CloudWatch Log Group for API Gateway access logs
        // -----------------------------------------------------------------------
        LogGroup apiAccessLogGroup = LogGroup.Builder.create(this, "ApiAccessLogGroup")
            .logGroupName("/aws/apigateway/eks-d-xpress")
            .retention(RetentionDays.ONE_MONTH)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // -----------------------------------------------------------------------
        // REST API — IAM auth by default, per-route overrides below
        // -----------------------------------------------------------------------
        RestApi api = RestApi.Builder.create(this, "EksDxApi")
            .restApiName("eks-d-xpress")
            .deployOptions(StageOptions.builder()
                .stageName("prod")
                .accessLogDestination(new LogGroupLogDestination(apiAccessLogGroup))
                .accessLogFormat(AccessLogFormat.jsonWithStandardFields())
                .loggingLevel(MethodLoggingLevel.INFO)
                .build())
            .defaultMethodOptions(MethodOptions.builder()
                .authorizationType(AuthorizationType.IAM)
                .build())
            .build();

        // -----------------------------------------------------------------------
        // Lambda: credential service  (hot path — SnapStart)
        // -----------------------------------------------------------------------
        LogGroup credentialLogGroup = LogGroup.Builder.create(this, "CredentialFnLogGroup")
            .logGroupName("/aws/lambda/eks-d-xpress-credential-service")
            .retention(RetentionDays.ONE_MONTH)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // Fixed-name broker role — trust anchor for Pod Identity-compatible trust policies
        Role credentialBrokerRole = Role.Builder.create(this, "EksDXCredentialBrokerRole")
            .roleName("EksDXCredentialBroker")
            .assumedBy(new ServicePrincipal("lambda.amazonaws.com"))
            .build();

        Function credentialFn = Function.Builder.create(this, "EksDxCredentialFunction")
            .functionName("eks-d-xpress-credential-service")
            .runtime(Runtime.JAVA_25)
            .handler("io.quarkus.amazon.lambda.runtime.QuarkusStreamHandler::handleRequest")
            .code(Code.fromAsset(credentialZip))
            .memorySize(512)
            .timeout(Duration.seconds(30))
            .role(credentialBrokerRole)
            .environment(Map.of(
                "EKS_DX_CLUSTERS_TABLE", clustersTable.getTableName(),
                "EKS_DX_ASSOCIATIONS_TABLE", associationsTable.getTableName(),
                "AWS_ACCOUNT_ID", Aws.ACCOUNT_ID))
            .logGroup(credentialLogGroup)
            .build();

        // SnapStart on published versions
        CfnFunction cfnCredential = (CfnFunction) credentialFn.getNode().getDefaultChild();
        cfnCredential.addPropertyOverride("SnapStart", Map.of("ApplyOn", "PublishedVersions"));

        // IAM: GetItem only (not full CRUD) — credential path is read-only on DynamoDB
        credentialFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("dynamodb:GetItem"))
            .resources(List.of(clustersTable.getTableArn(), associationsTable.getTableArn()))
            .build());
        // Pod Identity-compatible broker: AssumeRole + TagSession + SetSourceIdentity
        // No role-name prefix constraint — scoping is via session tag conditions on target trust policies
        credentialFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"))
            .resources(List.of("*"))
            .build());
        // CloudWatch Logs (required since we provide explicit role)
        credentialFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"))
            .resources(List.of("*"))
            .build());

        // -----------------------------------------------------------------------
        // Lambda: mgmt service  (cluster/association CRUD)
        // -----------------------------------------------------------------------
        LogGroup mgmtLogGroup = LogGroup.Builder.create(this, "MgmtFnLogGroup")
            .logGroupName("/aws/lambda/eks-d-xpress-mgmt-service")
            .retention(RetentionDays.ONE_MONTH)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        Function mgmtFn = Function.Builder.create(this, "EksDxMgmtFunction")
            .functionName("eks-d-xpress-mgmt-service")
            .runtime(Runtime.JAVA_25)
            .handler("io.quarkus.amazon.lambda.runtime.QuarkusStreamHandler::handleRequest")
            .code(Code.fromAsset(mgmtZip))
            .memorySize(256)
            .timeout(Duration.seconds(30))
            .environment(Map.of(
                "EKS_DX_CLUSTERS_TABLE", clustersTable.getTableName(),
                "EKS_DX_ASSOCIATIONS_TABLE", associationsTable.getTableName(),
                "AWS_ACCOUNT_ID", Aws.ACCOUNT_ID))
            .logGroup(mgmtLogGroup)
            .build();

        clustersTable.grantReadWriteData(mgmtFn);
        associationsTable.grantReadWriteData(mgmtFn);
        mgmtFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("iam:GetRole", "iam:ListRoleTags"))
            .resources(List.of("arn:aws:iam::*:role/*"))
            .build());
        // Trust policy management — scoped to roles tagged eks-dx-managed=true
        mgmtFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("iam:UpdateAssumeRolePolicy"))
            .resources(List.of(String.format("arn:aws:iam::%s:role/*", Aws.ACCOUNT_ID)))
            .conditions(Map.of(
                "StringEquals", Map.of("iam:ResourceTag/eks-dx-managed", "true")))
            .build());

        // -----------------------------------------------------------------------
        // Lambda: tenant service  (GraalVM native, arm64, SSE via Function URL)
        // -----------------------------------------------------------------------
        // Context flags:
        //   -c nativeArch=x86   → GraalVM native on x86_64 (build without -Pnative on arm64)
        //   -c jvmTenant=true   → JVM mode on x86_64 (skip native build entirely)
        //   (default)           → GraalVM native on arm64 (prod)
        boolean jvmMode = "true".equals(this.getNode().tryGetContext("jvmTenant"));
        boolean x86Native = "x86".equals(this.getNode().tryGetContext("nativeArch"));
        boolean dryRun = "true".equals(this.getNode().tryGetContext("dryRun"));
        Runtime tenantRuntime = jvmMode ? Runtime.JAVA_25 : Runtime.PROVIDED_AL2023;
        Architecture tenantArch = (jvmMode || x86Native) ? Architecture.X86_64 : Architecture.ARM_64;
        // Write the API endpoint to SSM so EC2 instances can read it at boot
        // without baking it into user data (decouples endpoint from instance launch).
        String endpointParamName = "/eks-d-xpress/control-plane/api/endpoint";
        StringParameter.Builder.create(this, "ApiEndpointParam")
            .parameterName(endpointParamName)
            .stringValue(api.getUrl())
            .description("EKS-DX API Gateway endpoint — read by EC2 instances at boot")
            .build();

        // Quota: max tenants per caller identity (ownership isolation)
        var maxTenantsPerCaller = StringParameter.Builder.create(this, "MaxTenantsPerCallerParam")
            .parameterName("/eks-d-xpress/control-plane/quota/max-tenants-per-caller")
            .stringValue("1")
            .description("Maximum tenants a single IAM identity can provision")
            .build();

        LogGroup tenantLogGroup = LogGroup.Builder.create(this, "TenantFnLogGroup")
            .logGroupName("/aws/lambda/eks-d-xpress-tenant-service")
            .retention(RetentionDays.ONE_MONTH)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // Lambda Web Adapter layer — bridges HTTP server to Lambda streaming Runtime API
        String region = this.getRegion();
        String webAdapterLayerArn = tenantArch == Architecture.ARM_64
            ? "arn:aws:lambda:" + region + ":753240598075:layer:LambdaAdapterLayerArm64:25"
            : "arn:aws:lambda:" + region + ":753240598075:layer:LambdaAdapterLayerX86:25";
        var webAdapterLayer = LayerVersion.fromLayerVersionArn(this, "LambdaWebAdapter", webAdapterLayerArn);

        // With Web Adapter: JVM mode uses java25 runtime + EXEC_WRAPPER,
        // native mode uses provided.al2023 (binary is the HTTP server)
        Function tenantFn = Function.Builder.create(this, "EksDxTenantFunction")
            .functionName("eks-d-xpress-tenant-service")
            .runtime(jvmMode ? Runtime.JAVA_25 : Runtime.PROVIDED_AL2023)
            .architecture(tenantArch)
            .handler(jvmMode ? "run.sh" : "bootstrap")
            .code(Code.fromAsset(tenantZip))
            .layers(List.of(webAdapterLayer))
            .memorySize(jvmMode ? 512 : 256)
            .timeout(Duration.seconds(900))
            .environment(java.util.Map.ofEntries(
                Map.entry("EKS_DX_TENANTS_TABLE", tenantsTable.getTableName()),
                Map.entry("EKS_DX_CLUSTERS_TABLE", clustersTable.getTableName()),
                Map.entry("EKS_DX_LT_ARM64_ONDEMAND", ltArm64Ondemand),
                Map.entry("EKS_DX_LT_ARM64_SPOT", ltArm64Spot),
                Map.entry("EKS_DX_LT_X86_ONDEMAND", ltX86Ondemand),
                Map.entry("EKS_DX_LT_X86_SPOT", ltX86Spot),
                Map.entry("EKS_DX_VPC_ID", vpcId),
                Map.entry("EKS_DX_AVAILABILITY_ZONE", "auto"),
                Map.entry("EKS_DX_DRY_RUN", String.valueOf(dryRun)),
                Map.entry("EKS_DX_MAX_TENANTS_PER_CALLER", maxTenantsPerCaller.getStringValue()),
                Map.entry("AWS_LWA_INVOKE_MODE", "response_stream"),
                Map.entry("AWS_LAMBDA_EXEC_WRAPPER", "/opt/bootstrap"),
                Map.entry("READINESS_CHECK_PATH", "/q/health/ready"),
                Map.entry("PORT", "8080")))
            .logGroup(tenantLogGroup)
            .build();

        // Single Function URL for both SSE stream and provisioning — bypasses API Gateway's 29s timeout.
        // RESPONSE_STREAM mode supports both streaming (SSE) and buffered responses.
        FunctionUrl tenantFunctionUrl = tenantFn.addFunctionUrl(FunctionUrlOptions.builder()
            .authType(FunctionUrlAuthType.AWS_IAM)
            .invokeMode(InvokeMode.RESPONSE_STREAM)
            .build());

        StringParameter.Builder.create(this, "TenantStreamUrlParam")
            .parameterName("/eks-d-xpress/control-plane/api/stream-url")
            .stringValue(tenantFunctionUrl.getUrl())
            .description("EKS-DX tenant Function URL — used for both SSE stream and provisioning")
            .build();

        // Provisioning URL reuses the same Function URL (Lambda supports only one Function URL)
        StringParameter.Builder.create(this, "TenantProvisioningUrlParam")
            .parameterName("/eks-d-xpress/control-plane/api/provisioning-url")
            .stringValue(tenantFunctionUrl.getUrl())
            .description("EKS-DX tenant provisioning Function URL — same as stream URL")
            .build();

        tenantsTable.grantReadWriteData(tenantFn);
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("dynamodb:DeleteItem"))
            .resources(List.of(clustersTable.getTableArn()))
            .build());
        // EC2: read-only on shared VPC infrastructure (Describe actions require Resource:"*" in IAM)
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeRouteTables",
                "ec2:DescribeSecurityGroups", "ec2:DescribeAddresses"))
            .resources(List.of("*"))
            .build());
        // EC2: mutating actions scoped to shared VPC
        String vpcArn = String.format("arn:aws:ec2:%s:%s:vpc/%s",
            Stack.of(this).getRegion(), Stack.of(this).getAccount(), vpcId);
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "ec2:CreateSubnet", "ec2:DeleteSubnet",
                "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress", "ec2:AssociateRouteTable"))
            .resources(List.of(vpcArn,
                String.format("arn:aws:ec2:%s:%s:subnet/*", Stack.of(this).getRegion(), Stack.of(this).getAccount()),
                String.format("arn:aws:ec2:%s:%s:security-group/*", Stack.of(this).getRegion(), Stack.of(this).getAccount()),
                String.format("arn:aws:ec2:%s:%s:route-table/*", Stack.of(this).getRegion(), Stack.of(this).getAccount())))
            .build());
        // EC2: instance lifecycle + EIP/key creation (resources don't exist yet at creation time)
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "ec2:RunInstances", "ec2:TerminateInstances",
                "ec2:StopInstances", "ec2:StartInstances",
                "ec2:CreateKeyPair",
                "ec2:DescribeInstances", "ec2:CreateTags",
                "ec2:AllocateAddress", "ec2:AssociateAddress"))
            .resources(List.of("*"))
            .build());
        // EC2: EIP release/disassociate — scoped to EIPs tagged project=eks-d-xpress
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("ec2:ReleaseAddress", "ec2:DisassociateAddress"))
            .resources(List.of(String.format("arn:aws:ec2:%s:%s:elastic-ip/*",
                Stack.of(this).getRegion(), Stack.of(this).getAccount())))
            .conditions(Map.of("StringEquals", Map.of("aws:ResourceTag/project", "eks-d-xpress")))
            .build());
        // EC2: key pair deletion — scoped to key pairs tagged project=eks-d-xpress
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("ec2:DeleteKeyPair"))
            .resources(List.of(String.format("arn:aws:ec2:%s:%s:key-pair/*",
                Stack.of(this).getRegion(), Stack.of(this).getAccount())))
            .conditions(Map.of("StringEquals", Map.of("aws:ResourceTag/project", "eks-d-xpress")))
            .build());
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "iam:CreateRole", "iam:DeleteRole",
                "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:PassRole", "iam:TagRole",
                "iam:AttachRolePolicy", "iam:DetachRolePolicy",
                "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
                "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
                "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile"))
            .resources(List.of("arn:aws:iam::*:role/eks-d-xpress-tenant-*",
                "arn:aws:iam::*:instance-profile/eks-d-xpress-tenant-*"))
            .build());
        // DLM: etcd backup lifecycle policies
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "dlm:CreateLifecyclePolicy",
                "dlm:DeleteLifecyclePolicy",
                "dlm:GetLifecyclePolicies"))
            .resources(List.of("*"))
            .build());
        // SQS: Karpenter interruption queue
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("sqs:CreateQueue", "sqs:DeleteQueue", "sqs:GetQueueUrl"))
            .resources(List.of(String.format("arn:aws:sqs:%s:%s:eks-d-xpress-*",
                Stack.of(this).getRegion(), Stack.of(this).getAccount())))
            .build());
        // EventBridge: spot interruption rules
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "events:PutRule", "events:PutTargets",
                "events:RemoveTargets", "events:DeleteRule"))
            .resources(List.of(String.format("arn:aws:events:%s:%s:rule/eks-d-xpress-*",
                Stack.of(this).getRegion(), Stack.of(this).getAccount())))
            .build());
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "secretsmanager:CreateSecret",
                "secretsmanager:DeleteSecret",
                "secretsmanager:GetSecretValue"))
            .resources(List.of("arn:aws:secretsmanager:*:*:secret:eks-d-xpress/tenant/*"))
            .build());
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("sts:GetCallerIdentity"))
            .resources(List.of("*"))
            .build());
        tenantFn.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(List.of("ssm:GetParameter"))
            .resources(List.of(
                String.format("arn:aws:ssm:%s:%s:parameter%s",
                    Stack.of(this).getRegion(), Stack.of(this).getAccount(), endpointParamName),
                String.format("arn:aws:ssm:%s:%s:parameter/eks-d-xpress/infra/ami/*",
                    Stack.of(this).getRegion(), Stack.of(this).getAccount())))
            .build());

        // -----------------------------------------------------------------------
        // API routes — explicit methods with correct auth per route
        // -----------------------------------------------------------------------
        LambdaIntegration credentialInteg = new LambdaIntegration(credentialFn);
        LambdaIntegration mgmtInteg = new LambdaIntegration(mgmtFn);
        LambdaIntegration tenantInteg = new LambdaIntegration(tenantFn);

        MethodOptions iamAuth = MethodOptions.builder().authorizationType(AuthorizationType.IAM).build();
        MethodOptions noAuth = MethodOptions.builder().authorizationType(AuthorizationType.NONE).build();

        // /clusters
        IResource clusters = api.getRoot().addResource("clusters");
        clusters.addMethod("GET", mgmtInteg, iamAuth);
        clusters.addMethod("POST", mgmtInteg, iamAuth);

        // /clusters/{name}
        IResource clusterByName = clusters.addResource("{name}");
        clusterByName.addMethod("GET", mgmtInteg, iamAuth);
        clusterByName.addMethod("DELETE", mgmtInteg, iamAuth);

        // /clusters/{name}/jwks
        clusterByName.addResource("jwks").addMethod("PUT", mgmtInteg, iamAuth);

        // /clusters/{name}/assets  — OPEN (token validated by Lambda)
        clusterByName.addResource("assets").addMethod("POST", credentialInteg, noAuth);

        // /clusters/{name}/pod-identity-associations
        IResource associations = clusterByName.addResource("pod-identity-associations");
        associations.addMethod("GET", mgmtInteg, noAuth);
        associations.addMethod("POST", mgmtInteg, iamAuth);

        // /clusters/{name}/pod-identity-associations/{id}
        IResource associationById = associations.addResource("{id}");
        associationById.addMethod("GET", mgmtInteg, noAuth);
        associationById.addMethod("DELETE", mgmtInteg, iamAuth);

        // /tenants — tenant CRUD via HTTP API (v2 payload, matches quarkus-amazon-lambda-http)
        HttpApi tenantHttpApi = HttpApi.Builder.create(this, "TenantHttpApi")
            .apiName("eks-d-xpress-tenant-api")
            .build();

        HttpLambdaIntegration tenantHttpInteg = HttpLambdaIntegration.Builder.create("TenantHttpInteg", tenantFn)
            .build();

        HttpIamAuthorizer tenantIamAuth = new HttpIamAuthorizer();

        tenantHttpApi.addRoutes(AddRoutesOptions.builder()
            .path("/tenants")
            .methods(List.of(HttpMethod.POST))
            .integration(tenantHttpInteg)
            .authorizer(tenantIamAuth)
            .build());

        tenantHttpApi.addRoutes(AddRoutesOptions.builder()
            .path("/tenants/{id}")
            .methods(List.of(HttpMethod.GET, HttpMethod.DELETE))
            .integration(tenantHttpInteg)
            .authorizer(tenantIamAuth)
            .build());

        StringParameter.Builder.create(this, "TenantApiUrlParam")
            .parameterName("/eks-d-xpress/control-plane/api/tenant-api-url")
            .stringValue(tenantHttpApi.getApiEndpoint())
            .description("EKS-DX tenant HTTP API URL — used for GET/DELETE /tenants/{id}")
            .build();

        // -----------------------------------------------------------------------
        // Custom domain (conditional)
        // -----------------------------------------------------------------------
        CfnDomainName cfnDomain = CfnDomainName.Builder.create(this, "ApiDomainName")
            .domainName(domainNameParam.getValueAsString())
            .regionalCertificateArn(certArnParam.getValueAsString())
            .endpointConfiguration(CfnDomainName.EndpointConfigurationProperty.builder()
                .types(List.of("REGIONAL")).build())
            .build();
        cfnDomain.getCfnOptions().setCondition(hasCustomDomain);

        CfnBasePathMapping cfnMapping = CfnBasePathMapping.Builder.create(this, "ApiMapping")
            .domainName(domainNameParam.getValueAsString())
            .restApiId(api.getRestApiId())
            .stage("prod")
            .build();
        cfnMapping.getCfnOptions().setCondition(hasCustomDomain);
        cfnMapping.addDependency(cfnDomain);

        // -----------------------------------------------------------------------
        // CloudWatch Alarms — named to match SAM
        // -----------------------------------------------------------------------
        Alarm.Builder.create(this, "CredentialErrorAlarm")
            .alarmName("eks-d-xpress-credential-errors")
            .metric(credentialFn.metricErrors(MetricOptions.builder().period(Duration.minutes(5)).statistic("Sum").build()))
            .threshold(5).evaluationPeriods(1)
            .treatMissingData(TreatMissingData.NOT_BREACHING).build();

        Alarm.Builder.create(this, "CredentialDurationAlarm")
            .alarmName("eks-d-xpress-credential-p99-duration")
            .metric(credentialFn.metricDuration(MetricOptions.builder().period(Duration.minutes(5)).statistic("p99").build()))
            .threshold(5000).evaluationPeriods(3)
            .treatMissingData(TreatMissingData.NOT_BREACHING).build();

        Alarm.Builder.create(this, "MgmtErrorAlarm")
            .alarmName("eks-d-xpress-mgmt-errors")
            .metric(mgmtFn.metricErrors(MetricOptions.builder().period(Duration.minutes(5)).statistic("Sum").build()))
            .threshold(5).evaluationPeriods(1)
            .treatMissingData(TreatMissingData.NOT_BREACHING).build();

        // -----------------------------------------------------------------------
        // Outputs
        // -----------------------------------------------------------------------
        CfnOutput.Builder.create(this, "Endpoint")
            .description("EKS-DX API endpoint")
            .value(api.getUrl()).build();

        CfnOutput.Builder.create(this, "CustomEndpoint")
            .description("Custom domain endpoint")
            .value("https://" + domainNameParam.getValueAsString())
            .condition(hasCustomDomain)
            .build();

        CfnOutput.Builder.create(this, "TenantStreamFunctionUrl")
            .description("Lambda Function URL for SSE tenant progress stream")
            .value(tenantFunctionUrl.getUrl()).build();

        CfnOutput.Builder.create(this, "ClustersTableName")
            .value(clustersTable.getTableName()).build();

        CfnOutput.Builder.create(this, "AssociationsTableName")
            .value(associationsTable.getTableName()).build();

        CfnOutput.Builder.create(this, "TenantsTableName")
            .value(tenantsTable.getTableName()).build();

        CfnOutput.Builder.create(this, "CredentialFunctionName")
            .value(credentialFn.getFunctionName()).build();

        CfnOutput.Builder.create(this, "MgmtFunctionName")
            .value(mgmtFn.getFunctionName()).build();

        CfnOutput.Builder.create(this, "TenantFunctionName")
            .value(tenantFn.getFunctionName()).build();

        CfnOutput.Builder.create(this, "EksDxCliPolicyResource")
            .description("IAM resource ARN for CLI execute-api:Invoke policy")
            .value(String.format("arn:aws:execute-api:%s:%s:%s/prod/*/*",
                Stack.of(this).getRegion(),
                Stack.of(this).getAccount(),
                api.getRestApiId()))
            .build();
    }
}

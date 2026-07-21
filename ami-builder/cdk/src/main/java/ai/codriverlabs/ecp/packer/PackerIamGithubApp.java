package ai.codriverlabs.ecp.packer;

import software.amazon.awscdk.App;
import software.amazon.awscdk.Environment;
import software.amazon.awscdk.StackProps;

public class PackerIamGithubApp {
    public static void main(String[] args) {
        var app = new App();

        new ExpressComputePackerIamStack(app, "ExpressComputePackerIamGithubStack", StackProps.builder()
                .env(Environment.builder()
                        .account(System.getenv("CDK_DEFAULT_ACCOUNT"))
                        .region(System.getenv("CDK_DEFAULT_REGION"))
                        .build())
                .build());

        app.synth();
    }
}

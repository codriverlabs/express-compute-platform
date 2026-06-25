package cloud.plasticity.eksdx;

import software.amazon.awscdk.App;
import software.amazon.awscdk.Environment;
import software.amazon.awscdk.StackProps;

public class EksDxApp {
    public static void main(String[] args) {
        App app = new App();

        var env = Environment.builder()
                .account(System.getenv("CDK_DEFAULT_ACCOUNT"))
                .region(System.getenv("CDK_DEFAULT_REGION"))
                .build();

        new SharedInfraStack(app, "EksDxSharedInfraStack", StackProps.builder()
                .env(env).build());

        app.synth();
    }
}

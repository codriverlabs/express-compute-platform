FROM public.ecr.aws/amazoncorretto/amazoncorretto:25.0.3-al2023-headless

# al2023 ships python3, aws-cli and openssl — only additional tools needed are Node.js/npm, Helm and Maven
RUN dnf install -y nodejs22 npm maven unzip tar gzip findutils && dnf clean all

# CDK CLI + Helm
RUN npm install -g aws-cdk \
    && curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

WORKDIR /opt/eks-dx

# Infra: tarball includes pre-synthesized cdk.out + helper scripts
COPY infra-cdk/ ./

# Control-plane: source only — build and synthesize at image build time
COPY control-plane-cdk/ ./control-plane/
RUN cd /opt/eks-dx/control-plane/infra \
    && mvn package -q -DskipTests \
    && cdk synth --output /opt/eks-dx/control-plane/cdk.out

# AMI manifest + signing public key + signatures (for verify-ami / import-ami)
COPY ami-manifest.json ./ami-manifest.json
COPY ami-signatures.json ./ami-signatures.json
COPY eks-d-xpress-ami-signing.pub.pem ./eks-d-xpress-ami-signing.pub.pem

# Helm charts
COPY helm/ ./helm/

# CLI binary (arch-matched via buildx)
COPY eks-dx-cli ./bin/eks-dx
RUN chmod +x ./bin/eks-dx

# AMI utility scripts
COPY verify-ami.sh  ./bin/verify-ami.sh
COPY import-ami.sh  ./bin/import-ami.sh
RUN chmod +x ./bin/verify-ami.sh ./bin/import-ami.sh

# Orchestrator
COPY deploy.sh ./deploy.sh
RUN chmod +x ./deploy.sh

ENV PATH="/opt/eks-dx/bin:${PATH}"

ENTRYPOINT ["/opt/eks-dx/deploy.sh"]
CMD ["--help"]

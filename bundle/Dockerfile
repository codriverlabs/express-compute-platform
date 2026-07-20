# public.ecr.aws/amazoncorretto/amazoncorretto:25.0.3-al2023-headless (use if JVM needed)
FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# al2023 ships python3 — only Node.js/npm and Helm needed
RUN dnf install -y nodejs22 aws-cli unzip tar gzip findutils less && dnf clean all

# CDK CLI + Helm
RUN npm install -g aws-cdk \
    && curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

WORKDIR /opt/ecp

# Infra: pre-synthesized cdk.out bundled in release tarball
COPY infra-cdk/ ./

# Control-plane: pre-synthesized cdk.out bundled in release tarball
COPY control-plane-cdk/ ./control-plane/

# AMI manifest + signing public key + signatures (for verify-ami / import-ami)
COPY ami-manifest.json ./ami-manifest.json
COPY ami-signatures.json ./ami-signatures.json
COPY express-compute-ami-signing.pub.pem ./express-compute-ami-signing.pub.pem

# Helm charts
COPY helm/ ./helm/

# CLI binary (arch-matched via buildx)
COPY ecp-cli ./bin/ecp
RUN chmod +x ./bin/ecp

# AMI utility scripts
COPY verify-ami.sh  ./bin/verify-ami.sh
COPY import-ami.sh  ./bin/import-ami.sh
RUN chmod +x ./bin/verify-ami.sh ./bin/import-ami.sh

# Orchestrator
COPY deploy.sh ./deploy.sh
RUN chmod +x ./deploy.sh

ENV PATH="${PATH}:/opt/ecp/bin"

ENTRYPOINT ["/opt/ecp/deploy.sh"]
CMD ["--help"]

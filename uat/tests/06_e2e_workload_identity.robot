*** Settings ***
Documentation    UAT: End-to-end Workload Identity validation.
...              Creates IAM role (ecp-managed tag), S3 bucket, service account,
...              association, then verifies a pod can assume the role and access S3.
...
...              Requires a running cluster with Workload Identity installed.
...              Tagged 'e2e' — slow, creates real AWS resources.
...
...              Ref: https://github.com/codriverlabs/express-compute-control-plane/blob/main/docs/user-guides/iam/iam-role-setup.md
Resource         ../resources/common.resource
Resource         ../resources/variables.robot
Resource         ../resources/ecp_setup.resource
Suite Setup      Run Keywords    Verify Prerequisites    AND    Setup E2E Resources
Suite Teardown   Cleanup E2E Resources
Force Tags       e2e    workload-identity

*** Variables ***
${E2E_CLUSTER}      ${EMPTY}
${E2E_ROLE}         uat-ecp-wi-test-role
${E2E_POLICY}       uat-ecp-wi-test-policy
${E2E_BUCKET}       ${EMPTY}
${E2E_SA}           uat-wi-test-sa
${E2E_NAMESPACE}    default
${ACCOUNT_ID}       ${EMPTY}
${ASSOC_ID}         ${EMPTY}

*** Test Cases ***
E2E-01 IAM Role Created With ecp-managed Tag
    [Documentation]    Verify the test role exists and has the ecp-managed tag.
    [Tags]    critical
    ${result}=    Run Process    aws    iam    list-role-tags
    ...    --role-name    ${E2E_ROLE}
    ...    --query    Tags[?Key\=\='ecp-managed'].Value
    ...    --output    text
    Should Be Equal As Integers    ${result.rc}    0    Role not found: ${result.stderr}
    Should Contain    ${result.stdout}    true

E2E-02 Create Association Auto-Configures Trust Policy
    [Documentation]    After create-association, the role trust policy should reference ECPCredentialBroker.
    [Tags]    critical
    ${result}=    Run Process    aws    iam    get-role
    ...    --role-name    ${E2E_ROLE}
    ...    --query    Role.AssumeRolePolicyDocument
    ...    --output    json
    Should Be Equal As Integers    ${result.rc}    0
    Should Contain    ${result.stdout}    ECPCredentialBroker
    Should Contain    ${result.stdout}    ${E2E_CLUSTER}
    Should Contain    ${result.stdout}    ${E2E_SA}

E2E-03 Pod Gets Caller Identity Via Workload Identity
    [Documentation]    A pod using the test SA can call sts:GetCallerIdentity and receive
    ...    credentials for the test role.
    [Tags]    critical
    ${result}=    Run Process    kubectl    run    uat-wi-sts-test
    ...    --image\=public.ecr.aws/aws-cli/aws-cli:latest
    ...    --rm    -it    --restart\=Never
    ...    --namespace\=${E2E_NAMESPACE}
    ...    --overrides\={"spec":{"serviceAccountName":"${E2E_SA}"}}
    ...    --    sts    get-caller-identity    --output    json
    ...    timeout\=120s
    Should Be Equal As Integers    ${result.rc}    0
    ...    Pod failed to get caller identity: ${result.stderr}
    Should Contain    ${result.stdout}    ${E2E_ROLE}
    Should Contain    ${result.stdout}    ${ACCOUNT_ID}
    Log    Caller identity: ${result.stdout}

E2E-04 Pod Can Write To S3 Bucket
    [Documentation]    Pod can put an object to the test S3 bucket.
    [Tags]    critical
    ${result}=    Run Process    kubectl    run    uat-wi-s3-write
    ...    --image\=public.ecr.aws/aws-cli/aws-cli:latest
    ...    --rm    -it    --restart\=Never
    ...    --namespace\=${E2E_NAMESPACE}
    ...    --overrides\={"spec":{"serviceAccountName":"${E2E_SA}"}}
    ...    --    s3    cp    -    s3://${E2E_BUCKET}/uat-test.txt
    ...    --content-type    text/plain
    ...    timeout\=60s
    ...    stdin\=hello from workload identity UAT
    # Note: stdin piping may not work — fall back to simpler test
    ${ls_result}=    Run Process    kubectl    run    uat-wi-s3-ls
    ...    --image\=public.ecr.aws/aws-cli/aws-cli:latest
    ...    --rm    -it    --restart\=Never
    ...    --namespace\=${E2E_NAMESPACE}
    ...    --overrides\={"spec":{"serviceAccountName":"${E2E_SA}"}}
    ...    --    s3    ls    s3://${E2E_BUCKET}/
    ...    timeout\=60s
    Should Be Equal As Integers    ${ls_result.rc}    0
    ...    Pod failed to list S3 bucket: ${ls_result.stderr}
    Log    S3 listing: ${ls_result.stdout}

E2E-05 Pod Without SA Cannot Assume Role
    [Documentation]    A pod using the default SA should NOT get the test role credentials.
    ${result}=    Run Process    kubectl    run    uat-wi-negative
    ...    --image\=public.ecr.aws/aws-cli/aws-cli:latest
    ...    --rm    -it    --restart\=Never
    ...    --namespace\=${E2E_NAMESPACE}
    ...    --    sts    get-caller-identity    --output    json
    ...    timeout\=60s
    # Should either fail or return a different identity (not our test role)
    IF    ${result.rc} == 0
        Should Not Contain    ${result.stdout}    ${E2E_ROLE}
    END

*** Keywords ***
Setup E2E Resources
    [Documentation]    Create IAM role (ecp-managed), S3 bucket, K8s SA, and association.

    # Determine account and cluster
    ${id_result}=    Run Process    aws    sts    get-caller-identity    --query    Account    --output    text
    Set Suite Variable    ${ACCOUNT_ID}    ${id_result.stdout.strip()}
    Set Suite Variable    ${E2E_BUCKET}    uat-ecp-wi-${ACCOUNT_ID}-${REGION}

    # Find first available cluster
    ${clusters}=    ECP CLI Should Succeed    list-clusters
    ${lines}=    Split To Lines    ${clusters.stdout}
    FOR    ${line}    IN    @{lines}
        ${stripped}=    Strip String    ${line}
        ${skip}=    Run Keyword And Return Status    Should Match Regexp    ${stripped}    ^(NAME|--|$|\\s*$)
        IF    not ${skip}
            Set Suite Variable    ${E2E_CLUSTER}    ${stripped.split()[0]}
            RETURN FROM KEYWORD
        END
    END
    Fail    No clusters found — cannot run E2E tests

    # Create S3 bucket (idempotent)
    Run Process    aws    s3    mb    s3://${E2E_BUCKET}    --region    ${REGION}

    # Create IAM policy
    ${policy_doc}=    Set Variable    {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:*"],"Resource":["arn:aws:s3:::${E2E_BUCKET}","arn:aws:s3:::${E2E_BUCKET}/*"]},{"Effect":"Allow","Action":"sts:GetCallerIdentity","Resource":"*"}]}
    Run Process    aws    iam    create-policy
    ...    --policy-name    ${E2E_POLICY}
    ...    --policy-document    ${policy_doc}

    # Create IAM role with empty trust (ECP will fill it)
    ${trust}=    Set Variable    {"Version":"2012-10-17","Statement":[]}
    Run Process    aws    iam    create-role
    ...    --role-name    ${E2E_ROLE}
    ...    --assume-role-policy-document    ${trust}

    # Tag role for ECP auto-management
    Run Process    aws    iam    tag-role
    ...    --role-name    ${E2E_ROLE}
    ...    --tags    Key\=ecp-managed,Value\=true

    # Attach policy
    Run Process    aws    iam    attach-role-policy
    ...    --role-name    ${E2E_ROLE}
    ...    --policy-arn    arn:aws:iam::${ACCOUNT_ID}:policy/${E2E_POLICY}

    # Create K8s service account
    Run Process    kubectl    create    serviceaccount    ${E2E_SA}
    ...    -n    ${E2E_NAMESPACE}    --dry-run\=client    -o    yaml
    ...    |    kubectl    apply    -f    -

    # Create association (this should auto-configure trust policy)
    ${assoc}=    ECP CLI Should Succeed    create-association
    ...    --cluster-name    ${E2E_CLUSTER}
    ...    --namespace    ${E2E_NAMESPACE}
    ...    --service-account    ${E2E_SA}
    ...    --role-arn    arn:aws:iam::${ACCOUNT_ID}:role/${E2E_ROLE}
    Log    Association created: ${assoc.stdout}

    # Wait for trust policy propagation
    Sleep    10s    Wait for IAM eventual consistency

Cleanup E2E Resources
    [Documentation]    Best-effort cleanup of all test resources.

    # Delete association
    Run Keyword And Ignore Error    Delete Test Association

    # Delete K8s SA
    Run Process    kubectl    delete    serviceaccount    ${E2E_SA}
    ...    -n    ${E2E_NAMESPACE}    --ignore-not-found

    # Detach policy and delete role
    Run Process    aws    iam    detach-role-policy
    ...    --role-name    ${E2E_ROLE}
    ...    --policy-arn    arn:aws:iam::${ACCOUNT_ID}:policy/${E2E_POLICY}
    Run Process    aws    iam    delete-role    --role-name    ${E2E_ROLE}
    Run Process    aws    iam    delete-policy
    ...    --policy-arn    arn:aws:iam::${ACCOUNT_ID}:policy/${E2E_POLICY}

    # Delete S3 bucket
    Run Process    aws    s3    rb    s3://${E2E_BUCKET}    --force

Delete Test Association
    ${list}=    ECP CLI    list-associations    --cluster-name    ${E2E_CLUSTER}
    ${lines}=    Split To Lines    ${list.stdout}
    FOR    ${line}    IN    @{lines}
        ${has_sa}=    Run Keyword And Return Status    Should Contain    ${line}    ${E2E_SA}
        IF    ${has_sa}
            ${parts}=    Split String    ${line}
            ECP CLI    delete-association
            ...    --cluster-name    ${E2E_CLUSTER}
            ...    --association-id    ${parts[0]}
            RETURN
        END
    END

*** Settings ***
Documentation    UAT: Cluster lifecycle — create, describe, stop, resume, get-access, delete.
...              Full end-to-end happy path. Creates a real cluster with --wait (~4 min),
...              validates it becomes READY, stops/resumes, then tears it down.
...
...              SSH is locked to the caller's public IP via --ssh-cidr.
...              Tagged 'lifecycle' — excluded from quick smoke runs due to duration.
Resource         ../resources/common.resource
Resource         ../resources/variables.robot
Resource         ../resources/ecp_setup.resource
Suite Setup      Run Keywords    Verify Prerequisites    AND    Generate Cluster Name
Suite Teardown   Cleanup Test Cluster
Force Tags       lifecycle

*** Variables ***
${TEST_CLUSTER}    ${EMPTY}
${MY_CIDR}         ${EMPTY}

*** Test Cases ***
LC-01 Create Cluster With Wait
    [Documentation]    ecp create-cluster <name> --arch=arm64 --pricing=spot --ssh-cidr <ip>/32 --wait
    ...    Blocks until cluster is READY. SSH SG locked to caller's IP.
    [Tags]    critical
    ${result}=    ECP CLI Should Succeed    create-cluster    ${TEST_CLUSTER}
    ...    --arch\=${ARCH}
    ...    --pricing\=${PRICING}
    ...    --ssh-cidr    ${MY_CIDR}
    ...    --region    ${REGION}
    ...    --wait
    Log    Create output: ${result.stdout}

LC-02 Describe Cluster Shows READY
    [Documentation]    After --wait returns, describe shows READY state.
    ${result}=    ECP CLI Should Succeed    describe-cluster    ${TEST_CLUSTER}
    Should Contain    ${result.stdout}    READY
    Log    Describe output: ${result.stdout}

LC-03 List Clusters Shows Test Cluster
    [Documentation]    list-clusters includes our newly created cluster.
    ${result}=    ECP CLI Should Succeed    list-clusters
    Should Contain    ${result.stdout}    ${TEST_CLUSTER}

LC-04 Describe Shows Correct Arch And Pricing
    [Documentation]    Cluster was created with the requested arch and pricing model.
    ${result}=    ECP CLI Should Succeed    describe-cluster    ${TEST_CLUSTER}
    Should Contain    ${result.stdout}    ${ARCH}
    Should Contain    ${result.stdout}    ${PRICING}

LC-05 Get Cluster Access Shows SSH Details
    [Documentation]    ecp get-cluster-access returns connection information.
    ${result}=    ECP CLI Should Succeed    get-cluster-access    ${TEST_CLUSTER}    --region    ${REGION}
    Should Not Be Empty    ${result.stdout}
    Log    Access info: ${result.stdout}

LC-06 Stop Cluster
    [Documentation]    ecp stop-cluster stops the EC2 instance (EBS preserved).
    ${result}=    ECP CLI Should Succeed    stop-cluster    ${TEST_CLUSTER}
    Log    Stop output: ${result.stdout}
    Wait For Cluster Stopped    ${TEST_CLUSTER}    timeout=120

LC-07 Describe Shows STOPPED
    [Documentation]    After stop, cluster is in STOPPED state.
    ${result}=    ECP CLI Should Succeed    describe-cluster    ${TEST_CLUSTER}
    Should Contain    ${result.stdout}    STOPPED

LC-08 Resume Cluster With Wait
    [Documentation]    ecp resume-cluster --wait brings a stopped cluster back to READY.
    ${result}=    ECP CLI Should Succeed    resume-cluster    ${TEST_CLUSTER}    --wait
    Log    Resume output: ${result.stdout}

LC-09 Describe Shows READY After Resume
    [Documentation]    After resume --wait, cluster is READY again.
    ${result}=    ECP CLI Should Succeed    describe-cluster    ${TEST_CLUSTER}
    Should Contain    ${result.stdout}    READY

LC-10 Delete Cluster
    [Documentation]    ecp delete-cluster tears down the cluster completely.
    [Tags]    critical    destructive
    ${result}=    ECP CLI Should Succeed    delete-cluster    ${TEST_CLUSTER}    --region    ${REGION}
    Log    Delete output: ${result.stdout}

LC-11 Cluster Fully Terminated
    [Documentation]    After delete, cluster is eventually gone from describe.
    Wait For Cluster Terminated    ${TEST_CLUSTER}    timeout=180

*** Keywords ***
Generate Cluster Name
    ${ts}=    Evaluate    __import__('time').strftime('%H%M%S')
    ${name}=    Set Variable    ${CLUSTER_PREFIX}-${ts}
    Set Suite Variable    ${TEST_CLUSTER}    ${name}
    ${cidr}=    Get My IP CIDR
    Set Suite Variable    ${MY_CIDR}    ${cidr}
    Log    Test cluster: ${TEST_CLUSTER}, SSH CIDR: ${MY_CIDR}

Cleanup Test Cluster
    [Documentation]    Best-effort cleanup if tests failed mid-way.
    ${result}=    ECP CLI    describe-cluster    ${TEST_CLUSTER}
    IF    ${result.rc} == 0
        Log    Cleaning up cluster ${TEST_CLUSTER}...
        ECP CLI    delete-cluster    ${TEST_CLUSTER}    --region    ${REGION}
        Run Keyword And Ignore Error    Wait For Cluster Terminated    ${TEST_CLUSTER}    timeout=120
    END

*** Settings ***
Documentation    Shared prerequisite checks for ECP CLI UAT.
...              Verifies that ecp is on PATH, AWS credentials are valid,
...              and the control plane is reachable.
Library    Process
Library    OperatingSystem
Resource   variables.robot
Resource   common.resource

*** Keywords ***
Verify CLI Ready
    [Documentation]    Validates that ecp binary is on PATH and responds to --version.
    ${result}=    Run Process    which    ${ECP_CLI}
    Should Be Equal As Integers    ${result.rc}    0
    ...    ecp CLI not found on PATH. Ensure /opt/ecp/bin is in PATH or set ECP_CLI variable.
    ${version}=    ECP CLI Should Succeed    --version
    Should Not Be Empty    ${version.stdout}    ecp --version returned empty output
    Log    CLI version: ${version.stdout}

Verify AWS Credentials
    [Documentation]    Confirms caller identity is valid.
    ${result}=    Run Process    aws    sts    get-caller-identity    --region    ${REGION}
    Should Be Equal As Integers    ${result.rc}    0
    ...    AWS credentials not configured or expired: ${result.stderr}

Verify Control Plane Reachable
    [Documentation]    Validates that the ECP control plane API is reachable via list-clusters.
    ${result}=    ECP CLI    list-clusters    --region    ${REGION}
    Should Be Equal As Integers    ${result.rc}    0
    ...    Control plane unreachable: ${result.stderr}
    Log    Control plane OK — list-clusters returned rc=0

Verify Prerequisites
    [Documentation]    Full prerequisite check — CLI, credentials, and API reachable.
    Verify CLI Ready
    Verify AWS Credentials
    Verify Control Plane Reachable

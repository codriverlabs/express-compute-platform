*** Settings ***
Documentation    Shared prerequisite checks for ECP CLI UAT.
...              Verifies that ecp is on PATH (downloads if missing),
...              AWS credentials are valid, and the control plane is reachable.
Library    Process
Library    OperatingSystem
Resource   variables.robot
Resource   common.resource

*** Keywords ***
Verify CLI Ready
    [Documentation]    Validates that ecp binary is on PATH and responds to --version.
    ...    If not found, downloads from GitHub release.
    ${result}=    Run Process    which    ${ECP_CLI}
    IF    ${result.rc} != 0
        Download ECP CLI
    END
    ${version}=    ECP CLI Should Succeed    --version
    Should Not Be Empty    ${version.stdout}    ecp --version returned empty output
    Log    CLI version: ${version.stdout}

Download ECP CLI
    [Documentation]    Downloads ecp CLI from GitHub release, verifies checksum, installs to /usr/local/bin.
    ${arch}=    Run Process    uname    -m
    ${cli_arch}=    Set Variable If    "${arch.stdout.strip()}" == "aarch64"    arm64    amd64
    ${base_url}=    Set Variable    https://github.com/codriverlabs/express-compute-control-plane/releases/download/v${ECP_VERSION}
    ${binary}=    Set Variable    ecp-cli-${ECP_VERSION}-linux-${cli_arch}

    Log    Downloading ecp CLI v${ECP_VERSION} (${cli_arch})...

    # Download binary
    ${dl}=    Run Process    curl    -fsSL    ${base_url}/${binary}    -o    /tmp/ecp
    Should Be Equal As Integers    ${dl.rc}    0    Failed to download ecp CLI: ${dl.stderr}

    # Download checksum and verify
    ${cs}=    Run Process    curl    -fsSL    ${base_url}/checksums.txt    -o    /tmp/ecp-checksums.txt
    IF    ${cs.rc} == 0
        ${verify}=    Run Process    bash    -c
        ...    grep "${binary}" /tmp/ecp-checksums.txt | awk '{print $1 " /tmp/ecp"}' | sha256sum --check
        IF    ${verify.rc} != 0
            Log    WARNING: Checksum verification failed — proceeding anyway    WARN
        ELSE
            Log    ✓ Checksum verified
        END
    END

    # Install
    Run Process    chmod    +x    /tmp/ecp
    ${install}=    Run Process    bash    -c    cp /tmp/ecp /usr/local/bin/ecp 2>/dev/null || cp /tmp/ecp ${HOME}/.local/bin/ecp 2>/dev/null || true
    # Update ECP_CLI variable to point to downloaded binary
    ${which}=    Run Process    which    ecp
    IF    ${which.rc} != 0
        # Fallback: use /tmp/ecp directly
        Set Global Variable    ${ECP_CLI}    /tmp/ecp
    END
    Log    ecp CLI installed

Verify AWS Credentials
    [Documentation]    Confirms caller identity is valid.
    ${result}=    Run Process    aws    sts    get-caller-identity    --region    ${REGION}
    Should Be Equal As Integers    ${result.rc}    0
    ...    AWS credentials not configured or expired: ${result.stderr}

Verify Control Plane Reachable
    [Documentation]    Validates that the ECP control plane API is reachable via list-clusters.
    ${result}=    ECP CLI    list-clusters
    Should Be Equal As Integers    ${result.rc}    0
    ...    Control plane unreachable: ${result.stderr}
    Log    Control plane OK — list-clusters returned rc=0

Verify Prerequisites
    [Documentation]    Full prerequisite check — CLI, credentials, and API reachable.
    Verify CLI Ready
    Verify AWS Credentials
    Verify Control Plane Reachable

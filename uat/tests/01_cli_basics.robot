*** Settings ***
Documentation    UAT: CLI basics — version, help, error handling.
...              Validates that the ecp binary behaves correctly for basic
...              invocations before any infrastructure interaction.
Resource         ../resources/common.resource
Resource         ../resources/variables.robot
Force Tags       cli-basics

*** Test Cases ***
CLI-01 Version Flag Returns Version String
    [Documentation]    ecp --version prints a semver-like string and exits 0.
    [Tags]    smoke
    ${result}=    ECP CLI Should Succeed    --version
    Should Match Regexp    ${result.stdout}    \\d+\\.\\d+\\.\\d+
    Log    Version: ${result.stdout}

CLI-02 Help Flag Shows Usage
    [Documentation]    ecp --help prints usage information and lists subcommands.
    [Tags]    smoke
    ${result}=    ECP CLI Should Succeed    --help
    Should Contain    ${result.stdout}    Usage
    Should Contain    ${result.stdout}    create-cluster
    Should Contain    ${result.stdout}    list-clusters
    Should Contain    ${result.stdout}    describe-cluster

CLI-03 No Args Shows Missing Subcommand
    [Documentation]    ecp with no arguments reports missing required subcommand.
    ${result}=    ECP CLI    # no args
    Should Contain Any    ${result.stdout}    Missing required subcommand    Usage

CLI-04 Unknown Command Returns Non-Zero
    [Documentation]    Invoking a non-existent subcommand fails gracefully.
    ${result}=    ECP CLI Should Fail    nonexistent-command
    Should Not Be Empty    ${result.stderr}

CLI-05 Configure Shows Help
    [Documentation]    ecp configure --help explains endpoint/region setup.
    ${result}=    ECP CLI Should Succeed    configure    --help
    Should Contain Any    ${result.stdout}    endpoint    region    Configure

CLI-06 Create Cluster Help Shows Options
    [Documentation]    ecp create-cluster --help documents --arch, --pricing, --ssh-cidr, --wait.
    ${result}=    ECP CLI Should Succeed    create-cluster    --help
    Should Contain    ${result.stdout}    --arch
    Should Contain    ${result.stdout}    --pricing
    Should Contain    ${result.stdout}    --ssh-cidr
    Should Contain    ${result.stdout}    --wait

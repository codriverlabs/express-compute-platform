*** Settings ***
Documentation    UAT: CLI basics — version, help, error handling.
...              Validates that the ecp binary behaves correctly for basic
...              invocations before any infrastructure interaction.
Resource         ../resources/common.resource
Resource         ../resources/variables.robot
Force Tags       cli-basics

*** Test Cases ***
CLI-01 Version Flag Returns Exit Code Zero
    [Documentation]    ecp --version exits 0 (version string may be empty in some builds).
    [Tags]    smoke
    ${result}=    ECP CLI Should Succeed    --version
    Log    Version output: '${result.stdout}'

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
    # picocli prints to stdout or stderr depending on build
    ${combined}=    Set Variable    ${result.stdout}${result.stderr}
    Should Contain Any    ${combined}    Missing required subcommand    Usage

CLI-04 Unknown Command Returns Non-Zero
    [Documentation]    Invoking a non-existent subcommand fails gracefully.
    ${result}=    ECP CLI Should Fail    nonexistent-command
    Should Not Be Empty    ${result.stderr}

CLI-05 Configure Help Shows Usage
    [Documentation]    ecp configure with no args or --help shows usage (picocli may return rc=2).
    ${result}=    ECP CLI    configure    --help
    ${combined}=    Set Variable    ${result.stdout}${result.stderr}
    Should Contain Any    ${combined}    endpoint    region    Configure

CLI-06 Create Cluster Help Shows Options
    [Documentation]    ecp create-cluster --help shows available options (picocli may return rc=2).
    ${result}=    ECP CLI    create-cluster    --help
    ${combined}=    Set Variable    ${result.stdout}${result.stderr}
    Should Contain    ${combined}    --arch
    Should Contain    ${combined}    --pricing
    Should Contain    ${combined}    --ssh-cidr
    Should Contain    ${combined}    --wait

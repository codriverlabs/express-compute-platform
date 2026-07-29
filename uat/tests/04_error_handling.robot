*** Settings ***
Documentation    UAT: Error handling and edge cases.
...              Validates that the CLI handles bad input gracefully.
Resource         ../resources/common.resource
Resource         ../resources/variables.robot
Resource         ../resources/ecp_setup.resource
Suite Setup      Verify CLI Ready
Force Tags       error-handling

*** Test Cases ***
ERR-01 Describe Non-Existent Cluster
    [Documentation]    describe-cluster for a missing cluster returns clear error.
    ${result}=    ECP CLI Should Fail    describe-cluster    this-cluster-does-not-exist-xyz    --region    ${REGION}
    Should Not Be Empty    ${result.stderr}

ERR-02 Delete Non-Existent Cluster
    [Documentation]    delete-cluster for a missing cluster returns clear error.
    ${result}=    ECP CLI Should Fail    delete-cluster    this-cluster-does-not-exist-xyz    --region    ${REGION}
    Should Not Be Empty    ${result.stderr}

ERR-03 Stop Non-Existent Cluster
    [Documentation]    stop-cluster for a missing cluster fails.
    ${result}=    ECP CLI Should Fail    stop-cluster    this-cluster-does-not-exist-xyz    --region    ${REGION}
    Should Not Be Empty    ${result.stderr}

ERR-04 Resume Non-Existent Cluster
    [Documentation]    resume-cluster for a missing cluster fails.
    ${result}=    ECP CLI Should Fail    resume-cluster    this-cluster-does-not-exist-xyz    --region    ${REGION}
    Should Not Be Empty    ${result.stderr}

ERR-05 Create Cluster Missing Name
    [Documentation]    create-cluster without a positional name fails.
    ${result}=    ECP CLI Should Fail    create-cluster    --region    ${REGION}    --arch\=${ARCH}
    Should Not Be Empty    ${result.stderr}

ERR-06 Create Cluster Invalid Arch
    [Documentation]    create-cluster with unsupported --arch value fails.
    ${result}=    ECP CLI Should Fail    create-cluster    bad-cluster
    ...    --arch\=sparc64    --region    ${REGION}
    Should Not Be Empty    ${result.stderr}

ERR-07 Create Association Missing Cluster
    [Documentation]    create-association without cluster name fails.
    ${result}=    ECP CLI Should Fail    create-association    --region    ${REGION}
    Should Not Be Empty    ${result.stderr}

ERR-08 List Associations Missing Cluster
    [Documentation]    list-associations without cluster name fails.
    ${result}=    ECP CLI Should Fail    list-associations    --region    ${REGION}
    Should Not Be Empty    ${result.stderr}

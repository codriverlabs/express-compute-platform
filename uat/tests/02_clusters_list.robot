*** Settings ***
Documentation    UAT: Cluster listing — validates ecp list-clusters and describe-cluster.
Resource         ../resources/common.resource
Resource         ../resources/variables.robot
Resource         ../resources/ecp_setup.resource
Suite Setup      Verify Prerequisites
Force Tags       clusters-list

*** Test Cases ***
LIST-01 List Clusters Returns Exit Code Zero
    [Documentation]    ecp list-clusters succeeds against deployed control plane.
    [Tags]    smoke
    ${result}=    ECP CLI Should Succeed    list-clusters
    Log    Output: ${result.stdout}

LIST-02 List Clusters With Invalid Region Fails
    [Documentation]    An invalid region in config causes failure.
    [Tags]    manual
    Skip    Requires reconfiguring region — would break other tests

LIST-03 Describe Cluster Requires Cluster Name
    [Documentation]    ecp describe-cluster without a positional name fails.
    ${result}=    ECP CLI Should Fail    describe-cluster
    Should Not Be Empty    ${result.stderr}

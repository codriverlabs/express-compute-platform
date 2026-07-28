*** Settings ***
Documentation    UAT: Workload Identity (Pod Identity Associations).
...              Requires a running cluster. Tests create-association, list, describe, delete.
...              Run after 03_cluster_lifecycle or against a pre-existing cluster.
Resource         ../resources/common.resource
Resource         ../resources/variables.robot
Resource         ../resources/ecp_setup.resource
Suite Setup      Run Keywords    Verify Prerequisites    AND    Verify Test Cluster Exists
Suite Teardown   Cleanup Associations
Force Tags       workload-identity

*** Variables ***
${WI_CLUSTER}       ${EMPTY}
${WI_NAMESPACE}     default
${WI_SA}            uat-test-sa
${WI_ROLE_ARN}      arn:aws:iam::123456789012:role/uat-dummy-role
${WI_ASSOC_ID}      ${EMPTY}

*** Test Cases ***
WI-01 Create Pod Identity Association
    [Documentation]    ecp create-association binds a service account to an IAM role.
    [Tags]    critical
    ${result}=    ECP CLI Should Succeed    create-association
    ...    --cluster-name    ${WI_CLUSTER}
    ...    --namespace    ${WI_NAMESPACE}
    ...    --service-account    ${WI_SA}
    ...    --role-arn    ${WI_ROLE_ARN}
    Log    Create output: ${result.stdout}
    # Extract association ID from output for subsequent commands
    ${id}=    Evaluate    [line for line in '''${result.stdout}'''.split('\\n') if 'association' in line.lower() or 'id' in line.lower()]
    Log    Parsed ID lines: ${id}

WI-02 List Associations Shows Created Entry
    [Documentation]    list-associations includes the association we just created.
    ${result}=    ECP CLI Should Succeed    list-associations
    ...    --cluster-name    ${WI_CLUSTER}
    Should Contain    ${result.stdout}    ${WI_SA}
    # Capture association ID from list for describe/delete
    ${lines}=    Split To Lines    ${result.stdout}
    FOR    ${line}    IN    @{lines}
        ${contains_sa}=    Run Keyword And Return Status    Should Contain    ${line}    ${WI_SA}
        IF    ${contains_sa}
            ${parts}=    Split String    ${line}
            Set Suite Variable    ${WI_ASSOC_ID}    ${parts[0]}
            Log    Association ID: ${WI_ASSOC_ID}
        END
    END

WI-03 List Associations With Namespace Filter
    [Documentation]    list-associations --namespace filters correctly.
    ${result}=    ECP CLI Should Succeed    list-associations
    ...    --cluster-name    ${WI_CLUSTER}
    ...    --namespace    ${WI_NAMESPACE}
    Should Contain    ${result.stdout}    ${WI_SA}

WI-04 Describe Association
    [Documentation]    describe-association returns details of the binding.
    Skip If    "${WI_ASSOC_ID}" == ""    Could not determine association ID from list
    ${result}=    ECP CLI Should Succeed    describe-association
    ...    --cluster-name    ${WI_CLUSTER}
    ...    --association-id    ${WI_ASSOC_ID}
    Should Contain    ${result.stdout}    ${WI_ROLE_ARN}

WI-05 Delete Association
    [Documentation]    delete-association removes the binding by ID.
    [Tags]    destructive
    Skip If    "${WI_ASSOC_ID}" == ""    Could not determine association ID from list
    ${result}=    ECP CLI Should Succeed    delete-association
    ...    --cluster-name    ${WI_CLUSTER}
    ...    --association-id    ${WI_ASSOC_ID}
    Log    Delete output: ${result.stdout}

WI-06 List After Delete Shows No Entry
    [Documentation]    After deletion, the service account no longer appears in list.
    ${result}=    ECP CLI Should Succeed    list-associations
    ...    --cluster-name    ${WI_CLUSTER}
    Should Not Contain    ${result.stdout}    ${WI_SA}

*** Keywords ***
Verify Test Cluster Exists
    [Documentation]    Checks that there is at least one cluster to test against.
    ...    Uses the first cluster from list-clusters, or fails with guidance.
    ${result}=    ECP CLI Should Succeed    list-clusters
    Should Not Be Empty    ${result.stdout}
    ...    No clusters found. Run 03_cluster_lifecycle first or deploy a cluster.
    ${lines}=    Split To Lines    ${result.stdout}
    FOR    ${line}    IN    @{lines}
        ${stripped}=    Strip String    ${line}
        ${skip}=    Run Keyword And Return Status    Should Match Regexp    ${stripped}    ^(NAME|--|$|\\s*$)
        IF    not ${skip}
            Set Suite Variable    ${WI_CLUSTER}    ${stripped.split()[0]}
            Log    Using cluster: ${WI_CLUSTER}
            RETURN
        END
    END
    Fail    Could not determine cluster name from list-clusters output

Cleanup Associations
    [Documentation]    Best-effort cleanup of test association.
    IF    "${WI_ASSOC_ID}" != ""
        Run Keyword And Ignore Error    ECP CLI    delete-association
        ...    --cluster-name    ${WI_CLUSTER}
        ...    --association-id    ${WI_ASSOC_ID}
    END

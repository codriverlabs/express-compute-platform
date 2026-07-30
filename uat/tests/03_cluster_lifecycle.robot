*** Settings ***
Documentation    UAT: Cluster lifecycle — create, validate SSH access, kubectl, delete.
...              Creates a real cluster with --wait (~4 min), validates SSH connectivity,
...              runs kubectl on the node, then tears it down.
...
...              SSH is locked to the caller's public IP via --ssh-cidr.
...              AMI: Amazon Linux 2023 (user: ec2-user)
...              Tagged 'lifecycle' — takes ~5 min total.
Resource         ../resources/common.resource
Resource         ../resources/variables.robot
Resource         ../resources/ecp_setup.resource
Suite Setup      Run Keywords    Verify Prerequisites    AND    Generate Cluster Name
Suite Teardown   Cleanup Test Cluster
Force Tags       lifecycle

*** Variables ***
${TEST_CLUSTER}    ${EMPTY}
${MY_CIDR}         ${EMPTY}
${CLUSTER_IP}      ${EMPTY}
${SSH_KEY_PATH}    ${EMPTY}

*** Test Cases ***
LC-01 Create Cluster
    [Documentation]    ecp create-cluster <name> --arch=arm64 --pricing=spot --ssh-cidr <ip>/32 --wait
    ...    Blocks until cluster is READY with progress streaming.
    [Tags]    critical
    [Timeout]    10 minutes
    ${result}=    ECP CLI Should Succeed    create-cluster    ${TEST_CLUSTER}
    ...    --arch\=${ARCH}
    ...    --pricing\=${PRICING}
    ...    --ssh-cidr    ${MY_CIDR}
    ...    --wait
    Log    Create output: ${result.stdout}
    # Extract IP and key path from create output
    ${ip}=    Evaluate    __import__('re').search(r'Public IP:\\s*(\\d+\\.\\d+\\.\\d+\\.\\d+)', '''${result.stdout}''')
    IF    ${ip}
        Set Suite Variable    ${CLUSTER_IP}    ${ip.group(1)}
    END
    ${key}=    Evaluate    __import__('re').search(r'SSH key:\\s*(.+\\.pem)', '''${result.stdout}''')
    IF    ${key}
        Set Suite Variable    ${SSH_KEY_PATH}    ${key.group(1).strip()}
    END

LC-02 Describe Cluster Shows Details
    [Documentation]    After --wait returns, describe shows cluster details.
    [Tags]    critical
    ${result}=    ECP CLI Should Succeed    describe-cluster    ${TEST_CLUSTER}
    Should Contain    ${result.stdout}    ${TEST_CLUSTER}
    Log    Describe output: ${result.stdout}

LC-03 List Clusters Shows Test Cluster
    [Documentation]    list-clusters includes our newly created cluster.
    ${result}=    ECP CLI Should Succeed    list-clusters
    Should Contain    ${result.stdout}    ${TEST_CLUSTER}

LC-04 Get Cluster Access Returns IP And SSH Command
    [Documentation]    ecp get-cluster-access returns the instance IP and SSH connection details.
    [Tags]    critical
    ${result}=    ECP CLI Should Succeed    get-cluster-access    ${TEST_CLUSTER}    --save-key
    Log    Access output: ${result.stdout}
    # If IP wasn't captured from create output, extract from get-cluster-access
    IF    "${CLUSTER_IP}" == ""
        ${ip}=    Evaluate    __import__('re').search(r'(\\d+\\.\\d+\\.\\d+\\.\\d+)', '''${result.stdout}''').group(1)
        Set Suite Variable    ${CLUSTER_IP}    ${ip}
    END
    IF    "${SSH_KEY_PATH}" == ""
        ${key}=    Evaluate    __import__('re').search(r'(/[\\w/.~-]+\\.pem)', '''${result.stdout}''')
        IF    ${key}
            Set Suite Variable    ${SSH_KEY_PATH}    ${key.group(1)}
        END
    END
    Log    IP: ${CLUSTER_IP}, Key: ${SSH_KEY_PATH}
    Should Not Be Empty    ${CLUSTER_IP}
    Should Not Be Empty    ${SSH_KEY_PATH}

LC-05 SSH Connectivity
    [Documentation]    SSH into the cluster node and verify connectivity.
    [Tags]    critical
    ${result}=    Run Process    ssh    -o    StrictHostKeyChecking\=no    -o    ConnectTimeout\=10
    ...    -i    ${SSH_KEY_PATH}    ${SSH_USER}@${CLUSTER_IP}    echo    ok
    Should Be Equal As Integers    ${result.rc}    0
    ...    SSH failed: ${result.stderr}
    Should Contain    ${result.stdout}    ok

LC-06 Kubectl Get Nodes Via SSH
    [Documentation]    Run kubectl get nodes on the cluster via SSH — should show Ready.
    [Tags]    critical
    ${result}=    Run Process    ssh    -o    StrictHostKeyChecking\=no
    ...    -i    ${SSH_KEY_PATH}    ${SSH_USER}@${CLUSTER_IP}
    ...    kubectl get nodes --no-headers
    Should Be Equal As Integers    ${result.rc}    0
    ...    kubectl get nodes failed: ${result.stderr}
    Should Contain    ${result.stdout}    Ready
    Log    Nodes: ${result.stdout}

LC-07 Kubectl Get Pods Kube-System Via SSH
    [Documentation]    Verify core system pods are running.
    ${result}=    Run Process    ssh    -o    StrictHostKeyChecking\=no
    ...    -i    ${SSH_KEY_PATH}    ${SSH_USER}@${CLUSTER_IP}
    ...    bash    -c    kubectl get pods -n kube-system --no-headers | grep -c Running
    Should Be Equal As Integers    ${result.rc}    0
    ${running_count}=    Convert To Integer    ${result.stdout.strip()}
    Should Be True    ${running_count} >= 5
    ...    Expected at least 5 running pods in kube-system, got ${running_count}
    Log    Running pods in kube-system: ${running_count}

LC-08 Deploy Test Workload Via SSH
    [Documentation]    Deploy a simple pod and verify it reaches Running state.
    ${result}=    Run Process    ssh    -o    StrictHostKeyChecking\=no
    ...    -i    ${SSH_KEY_PATH}    ${SSH_USER}@${CLUSTER_IP}
    ...    bash    -c    kubectl run uat-test --image\=public.ecr.aws/nginx/nginx:latest --restart\=Never && kubectl wait --for\=condition\=Ready pod/uat-test --timeout\=60s
    Should Be Equal As Integers    ${result.rc}    0
    ...    Deploy test workload failed: ${result.stderr}
    Log    Workload deploy: ${result.stdout}

LC-09 Kubectl Exec In Test Pod
    [Documentation]    kubectl exec into the test pod and verify it responds.
    ${result}=    Run Process    ssh    -o    StrictHostKeyChecking\=no
    ...    -i    ${SSH_KEY_PATH}    ${SSH_USER}@${CLUSTER_IP}
    ...    kubectl exec uat-test -- cat /etc/os-release
    Should Be Equal As Integers    ${result.rc}    0
    ...    kubectl exec failed: ${result.stderr}
    Should Contain Any    ${result.stdout}    Debian    Ubuntu    Alpine    Amazon
    Log    Pod OS: ${result.stdout}

LC-10 Cleanup Test Workload
    [Documentation]    Delete the test pod.
    ${result}=    Run Process    ssh    -o    StrictHostKeyChecking\=no
    ...    -i    ${SSH_KEY_PATH}    ${SSH_USER}@${CLUSTER_IP}
    ...    kubectl delete pod uat-test --ignore-not-found --timeout\=30s
    Should Be Equal As Integers    ${result.rc}    0

LC-11 Delete Cluster
    [Documentation]    ecp delete-cluster tears down the cluster completely.
    [Tags]    critical    destructive
    ${result}=    ECP CLI Should Succeed    delete-cluster    ${TEST_CLUSTER}    --region    ${REGION}
    Log    Delete output: ${result.stdout}

LC-12 Cluster Fully Terminated
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

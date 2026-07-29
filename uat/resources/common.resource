*** Settings ***
Documentation    Shared keywords for Express Compute CLI UAT.
...              Wraps ecp CLI invocations and common assertions.
Library    Process
Library    String
Library    OperatingSystem
Library    Collections

*** Keywords ***
ECP CLI
    [Documentation]    Run ecp CLI with given arguments. Returns Process result.
    [Arguments]    @{args}
    ${result}=    Run Process    ${ECP_CLI}    @{args}
    RETURN    ${result}

ECP CLI Should Succeed
    [Documentation]    Run ecp CLI and assert exit code 0.
    [Arguments]    @{args}
    ${result}=    ECP CLI    @{args}
    Should Be Equal As Integers    ${result.rc}    0
    ...    ecp ${args} failed (rc=${result.rc}): ${result.stderr}
    RETURN    ${result}

ECP CLI Should Fail
    [Documentation]    Run ecp CLI and assert non-zero exit code.
    [Arguments]    @{args}
    ${result}=    ECP CLI    @{args}
    Should Not Be Equal As Integers    ${result.rc}    0
    ...    Expected ecp ${args} to fail but got rc=0
    RETURN    ${result}

Get My IP CIDR
    [Documentation]    Returns caller's public IP as /32 CIDR for SSH lockdown.
    ${result}=    Run Process    curl    -s    https://checkip.amazonaws.com/
    Should Be Equal As Integers    ${result.rc}    0    Cannot determine public IP
    ${ip}=    Strip String    ${result.stdout}
    RETURN    ${ip}/32

Wait For Cluster Ready
    [Documentation]    Polls describe-cluster until output contains READY or timeout.
    ...    Note: describe-cluster does not accept --region (uses configured region).
    [Arguments]    ${name}    ${timeout}=300
    FOR    ${i}    IN RANGE    ${{int($timeout) // 10}}
        ${result}=    ECP CLI    describe-cluster    ${name}
        IF    ${result.rc} == 0
            ${has_ready}=    Run Keyword And Return Status    Should Contain    ${result.stdout}    READY
            IF    ${has_ready}
                RETURN
            END
        END
        Sleep    10s
    END
    Fail    Cluster ${name} did not reach READY within ${timeout}s

Wait For Cluster Stopped
    [Documentation]    Polls describe-cluster until output contains STOPPED or timeout.
    [Arguments]    ${name}    ${timeout}=180
    FOR    ${i}    IN RANGE    ${{int($timeout) // 10}}
        ${result}=    ECP CLI    describe-cluster    ${name}
        IF    ${result.rc} == 0
            ${has_stopped}=    Run Keyword And Return Status    Should Contain    ${result.stdout}    STOPPED
            IF    ${has_stopped}
                RETURN
            END
        END
        Sleep    10s
    END
    Fail    Cluster ${name} did not reach STOPPED within ${timeout}s

Wait For Cluster Terminated
    [Documentation]    Polls until describe-cluster fails (cluster gone) or timeout.
    [Arguments]    ${name}    ${timeout}=180
    FOR    ${i}    IN RANGE    ${{int($timeout) // 10}}
        ${result}=    ECP CLI    describe-cluster    ${name}
        IF    ${result.rc} != 0
            RETURN
        END
        Sleep    10s
    END
    Fail    Cluster ${name} still exists after ${timeout}s

Wait For Cluster Access
    [Documentation]    Polls get-cluster-access until it succeeds (cluster IP available) or timeout.
    [Arguments]    ${name}    ${timeout}=420
    FOR    ${i}    IN RANGE    ${{int($timeout) // 15}}
        ${result}=    ECP CLI    get-cluster-access    ${name}    --region    ${REGION}
        IF    ${result.rc} == 0
            ${has_ip}=    Evaluate    bool(__import__('re').search(r'\\d+\\.\\d+\\.\\d+\\.\\d+', '''${result.stdout}'''))
            IF    ${has_ip}
                Log    Cluster accessible: ${result.stdout}
                RETURN
            END
        END
        Sleep    15s
    END
    Fail    Cluster ${name} not accessible within ${timeout}s

*** Settings ***
Documentation    Express Compute Platform — CLI UAT
...
...    Validates that the ecp CLI works as documented for end users.
...    The ecp binary must be on PATH (not behind ./deploy.sh ecp).
...
...    Run all:   robot --outputdir results tests/
...    Run one:   robot --outputdir results tests/01_cli_basics.robot
...    Smoke:     robot --outputdir results -i smoke tests/
...
...    Override region:
...      robot --variable REGION:us-east-1 --outputdir results tests/
...
...    Prerequisites:
...      - ecp CLI on PATH
...      - Valid AWS credentials
...      - Control plane deployed in target region
Resource         ../resources/ecp_setup.resource
Suite Setup      Verify Prerequisites

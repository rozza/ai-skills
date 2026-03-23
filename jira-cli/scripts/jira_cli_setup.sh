#!/bin/bash

jira_cli_setup() {
    if [[ -z $JIRA_API_TOKEN ]]; then
        security find-generic-password -l jira-cli -w &>/dev/null
        if [[ $? -ne 0 ]]; then
            echo "No JIRA_API_TOKEN found in mac keychain. Set a new one."
             read -s "pass?Enter JIRA_API_TOKEN:"
            set -x
            security add-generic-password -a "${USER}" -l "jira-cli" -w "${pass}" -s $(uuidgen) -T "/usr/bin/security"
            unset pass
            { set +x; } &>/dev/null
            echo
        fi
        security find-generic-password -l jira-cli -w &>/dev/null
        if [[ $? -eq 0 ]]; then
            export JIRA_API_TOKEN=$(security find-generic-password -l jira-cli -w)
            export JIRA_AUTH_TYPE="bearer"
        else
            echo "no keychain pw for jira-cli"
        fi
    fi
}
jira_cli_setup

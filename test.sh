#!/bin/bash

LINTER_ERRORS_COUNTER="0"

### This works for local execution, not CircleCI
# REPO_NAME=$(basename `git rev-parse --show-toplevel`)
# BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
# STACK_NAME=${REPO_NAME}-${BRANCH_NAME}
# echo -e "STACK_NAME=" $STACK_NAME

# if [ "$BRANCH_NAME" == "master" ]; then {
#     echo -e "Test works for all branches except MASTER"
#     exit 1
# }
# fi

### This works for CircleCI, not local execution
STACK_NAME=${CIRCLE_PROJECT_REPONAME}-${CIRCLE_BRANCH}
echo -e "STACK_NAME=" $STACK_NAME

echo -e "Working with test env, setting appropriate variables.."
ENVIRONMENT="TEST"
AWS_REGION_TEST="us-east-1"
AWS_S3_BUCKET="aws-cloudformation-ec2-mssql"
AWS_EC2_INSTANCE_TYPE_TEST="t2.large"
echo -e "AWS_REGION_TEST="$AWS_REGION_TEST
echo -e "AWS_S3_BUCKET="$AWS_S3_BUCKET
echo -e "AWS_EC2_INSTANCE_TYPE_TEST="$AWS_EC2_INSTANCE_TYPE_TEST

function checkCommandExitCode {
    if [ $? -ne 0 ]; then {
        echo -e $1 "command has failed"
        exit 1
    }
    fi
}

function deleteStack {
    echo -e "Starting CloudFormation stack delete.."
    aws cloudformation delete-stack --region $AWS_REGION_TEST --stack-name $STACK_NAME
    checkCommandExitCode "CloudFormation stack delete"

    WAIT_RESULT=$(aws cloudformation wait stack-delete-complete --region $AWS_REGION_TEST --stack-name $STACK_NAME)
    if [ "$WAIT_RESULT" == "Waiter StackCreateComplete failed: Waiter encountered a terminal failure state" ]; then {
        echo -e "CloudFormation stack delete has failed"
        aws cloudformation describe-stack-events --region $AWS_REGION_TEST --stack-name $STACK_NAME
        exit 1
    } else {
        echo -e "CloudFormation stack delete has passed successfully"
    }
    fi
}

function runTests {
    echo -e "Starting CloudFormation Linter.."
    cfn-lint
    if [ $? -ne 0 ]; then {
        echo -e "CloudFormation Linter has failed"
        LINTER_ERRORS_COUNTER=$[$LINTER_ERRORS_COUNTER +1]
    } else {
        echo -e "CloudFormation Linter has passed successfully"
    }
    fi

    echo -e "Starting PSScriptAnalyzer.."
    pwsh -c "Invoke-ScriptAnalyzer -Path ./*.ps1 -ExcludeRule PSAvoidUsingConvertToSecureStringWithPlainText | Out-File -FilePath ./PWSH_LINT.txt"
    if [ -s ./PWSH_LINT.txt ]; then {
        cat ./PWSH_LINT.txt
        echo -e "PSScriptAnalyzer has failed"
        LINTER_ERRORS_COUNTER=$[$LINTER_ERRORS_COUNTER +1]
    } else {
        echo -e "PSScriptAnalyzer has passed successfully"
    }
    fi
    rm -f ./PWSH_LINT.txt
    checkCommandExitCode "Delete ./PWSH_LINT.txt file"

    if [ $LINTER_ERRORS_COUNTER -gt 0 ]; then {
        exit 1
    }
    fi
}

function createProdCopy {
    echo -e "Downloading root template from master branch.."
    git show master:root.yaml > master_root.yaml
    checkCommandExitCode "Downloading root template from master branch"

    echo -e "Starting CloudFormation stack create.."
    aws cloudformation create-stack \
        --region $AWS_REGION_TEST \
        --capabilities CAPABILITY_NAMED_IAM \
        --stack-name $STACK_NAME \
        --template-body file://master_root.yaml \
        --parameters \
        ParameterKey=NestedTemplateUrl,ParameterValue=https://s3.amazonaws.com/$AWS_S3_BUCKET/PROD/nested.yaml \
        ParameterKey=InstanceType,ParameterValue=$AWS_EC2_INSTANCE_TYPE_TEST \
        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        ParameterKey=BucketName,ParameterValue=$AWS_S3_BUCKET
    checkCommandExitCode "CloudFormation stack create"

    rm -f ./master_root.yaml
    checkCommandExitCode "Delete ./master_root.yaml file"

    WAIT_RESULT=$(aws cloudformation wait stack-create-complete --region $AWS_REGION_TEST --stack-name $STACK_NAME)
    if [ "$WAIT_RESULT" == "Waiter StackCreateComplete failed: Waiter encountered a terminal failure state" ]; then {
        echo -e "CloudFormation stack create has failed"
        aws cloudformation describe-stack-events --region $AWS_REGION_TEST --stack-name $STACK_NAME
        exit 1
    }
    fi

    DEPLOY_RESULT=$(aws cloudformation describe-stacks --region $AWS_REGION_TEST --stack-name $STACK_NAME | jq --raw-output '.Stacks | .[] | .StackStatus')
    if [ "$DEPLOY_RESULT" != "CREATE_COMPLETE" ]; then {
        echo -e "CloudFormation stack create has failed"
        aws cloudformation describe-stack-events --region $AWS_REGION_TEST --stack-name $STACK_NAME
        exit 1
    } else {
        echo -e "CloudFormation stack create has passed successfully"
    }
    fi
}

function updateProdCopy {
    aws s3 rm s3://$AWS_S3_BUCKET/$ENVIRONMENT/nested.yaml
    checkCommandExitCode "aws s3 rm"
    aws s3 rm s3://$AWS_S3_BUCKET/$ENVIRONMENT/scripts/attach-volumes.ps1
    checkCommandExitCode "aws s3 rm"
    aws s3 rm s3://$AWS_S3_BUCKET/$ENVIRONMENT/scripts/join-ad.ps1
    checkCommandExitCode "aws s3 rm"
    aws s3 rm s3://$AWS_S3_BUCKET/$ENVIRONMENT/scripts/rename-computer.ps1
    checkCommandExitCode "aws s3 rm"
    aws s3 cp nested.yaml s3://$AWS_S3_BUCKET/$ENVIRONMENT/nested.yaml
    checkCommandExitCode "aws s3 cp"
    aws s3 cp bootstrap-scripts/attach-volumes.ps1 s3://$AWS_S3_BUCKET/$ENVIRONMENT/scripts/attach-volumes.ps1
    checkCommandExitCode "aws s3 cp"
    aws s3 cp bootstrap-scripts/join-ad.ps1 s3://$AWS_S3_BUCKET/$ENVIRONMENT/scripts/join-ad.ps1
    checkCommandExitCode "aws s3 cp"
    aws s3 cp bootstrap-scripts/rename-computer.ps1 s3://$AWS_S3_BUCKET/$ENVIRONMENT/scripts/rename-computer.ps1
    checkCommandExitCode "aws s3 cp"

    echo -e "Starting CloudFormation stack update.."
    aws cloudformation update-stack \
        --region $AWS_REGION_TEST \
        --capabilities CAPABILITY_NAMED_IAM \
        --stack-name $STACK_NAME \
        --template-body file://root.yaml \
        --parameters \
        ParameterKey=NestedTemplateUrl,ParameterValue=https://s3.amazonaws.com/$AWS_S3_BUCKET/$ENVIRONMENT/nested.yaml \
        ParameterKey=InstanceType,ParameterValue=$AWS_EC2_INSTANCE_TYPE_TEST \
        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        ParameterKey=BucketName,ParameterValue=$AWS_S3_BUCKET
    checkCommandExitCode "CloudFormation stack update"

    WAIT_RESULT=$(aws cloudformation wait stack-update-complete --region $AWS_REGION_TEST --stack-name $STACK_NAME)
    if [ "$WAIT_RESULT" == "Waiter StackCreateComplete failed: Waiter encountered a terminal failure state" ]; then {
        echo -e "CloudFormation stack update has failed"
        aws cloudformation describe-stack-events --region $AWS_REGION_TEST --stack-name $STACK_NAME
        exit 1
    }
    fi

    DEPLOY_RESULT=$(aws cloudformation describe-stacks --region $AWS_REGION_TEST --stack-name $STACK_NAME | jq --raw-output '.Stacks | .[] | .StackStatus')
    if [ "$DEPLOY_RESULT" != "UPDATE_COMPLETE" ]; then {
        echo -e "CloudFormation stack update has failed"
        aws cloudformation describe-stack-events --region $AWS_REGION_TEST --stack-name $STACK_NAME
        exit 1
    } else {
        echo -e "CloudFormation stack update has passed successfully"
        deleteStack
    }
    fi
}

runTests
createProdCopy
updateProdCopy

#!/bin/bash

# Set the AWS profile to use 
export AWS_PROFILE=$1 # This sets the profile to use for the CLI commands or if you want change this to the profile you want to use but as is you must provide the profile as the first argument when running the script like this for example ./check_non_default.sh myprofilename
export AWS_REGION=us-east-1  # This sets a default region for CLI commands

# Get all AWS regions 
REGIONS=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)

# Initialize the JSON output
echo "[" > non_default_vpcs.json

# Print table header
printf "%-15s %-20s %-10s %-20s %-40s\n" "Region" "VpcId" "IsDefault" "Tag Key" "Tag Value"

FIRST_ENTRY=true

for REGION in $REGIONS; do
    echo "Checking region: $REGION"
    # Fetch VPC details with filters for non-default VPCs
    VPCS_JSON=$(aws ec2 describe-vpcs --region $REGION --filters "Name=isDefault,Values=false" --output json)
    
    # Iterate through each VPC
    echo "$VPCS_JSON" | jq -c '.Vpcs[]' | while read -r vpc; do
        vpc_id=$(echo "$vpc" | jq -r '.VpcId')
        is_default=$(echo "$vpc" | jq -r '.IsDefault')
        tags=$(echo "$vpc" | jq -r '.Tags // []')

        if [ "$tags" == "[]" ]; then
            printf "%-15s %-20s %-10s %-20s %-40s\n" "$REGION" "$vpc_id" "$is_default" "No Tags" ""
            if [ "$FIRST_ENTRY" = true ]; then
                FIRST_ENTRY=false
            else
                echo "," >> non_default_vpcs.json
            fi
            echo "{\"Region\": \"$REGION\", \"VpcId\": \"$vpc_id\", \"IsDefault\": $is_default, \"Tags\": []}" >> non_default_vpcs.json
        else
            TAGS_JSON="["
            for tag in $(echo "$tags" | jq -c '.[]'); do
                key=$(echo "$tag" | jq -r '.Key')
                value=$(echo "$tag" | jq -r '.Value')
                printf "%-15s %-20s %-10s %-20s %-40s\n" "$REGION" "$vpc_id" "$is_default" "$key" "$value"
                TAGS_JSON+="{\"Key\": \"$key\", \"Value\": \"$value\"},"
            done
            TAGS_JSON=${TAGS_JSON%,}
            TAGS_JSON+="]"
            if [ "$FIRST_ENTRY" = true ]; then
                FIRST_ENTRY=false
            else
                echo "," >> non_default_vpcs.json
            fi
            echo "{\"Region\": \"$REGION\", \"VpcId\": \"$vpc_id\", \"IsDefault\": $is_default, \"Tags\": $TAGS_JSON}" >> non_default_vpcs.json
        fi
    done
done

# Close JSON array
echo "]" >> non_default_vpcs.json

echo "JSON output saved to non_default_vpcs.json"

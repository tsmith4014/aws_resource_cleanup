#!/bin/bash

# Set the AWS profile to use 
export AWS_PROFILE=$1 # This sets the profile to use for the CLI commands or if you want change this to the profile you want to use but as is you must provide the profile as the first argument when running the script like this for example ./delete_vpc_resources.sh myprofilename
export AWS_REGION=us-west-2  # This sets a default region for CLI commands

# Check if a VPC ID is provided
if [ -z "$2" ]; then
    echo "Usage: $0 <vpc-id>"
    exit 1
fi

VPC_ID=$2 # This sets the VPC ID to use for the CLI commands or if you want change this to the VPC ID you want to use but as is you must provide the VPC ID as the second argument when running the script like this for example ./delete_vpc_resources.sh myprofilename vpc-1234567890abcdef0

echo "Deleting resources associated with VPC: $VPC_ID"

# Function to terminate instances in the VPC
terminate_instances() {
    echo "Terminating instances..."
    INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query "Reservations[*].Instances[*].InstanceId" --output text)
    if [ -n "$INSTANCE_IDS" ]; then
        aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
    fi
}

# Function to delete load balancers in the VPC
delete_load_balancers() {
    echo "Deleting load balancers..."
    LOAD_BALANCERS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text)
    for LB_ARN in $LOAD_BALANCERS; do
        echo "Deleting load balancer $LB_ARN..."
        aws elbv2 delete-load-balancer --load-balancer-arn $LB_ARN
    done

    # Wait for load balancers to be deleted
    for LB_ARN in $LOAD_BALANCERS; do
        while true; do
            LB_STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns $LB_ARN --query "LoadBalancers[0].State.Code" --output text 2>&1)
            if [[ "$LB_STATE" == "deleted" ]] || [[ "$LB_STATE" == *"LoadBalancerNotFound"* ]]; then
                echo "Load balancer $LB_ARN deleted."
                break
            fi
            echo "Waiting for load balancer $LB_ARN to be deleted..."
            sleep 10
        done
    done
}

# Function to wait for network interfaces to be available for deletion
wait_for_network_interfaces() {
    local ENIS=$1
    for ENI in $ENIS; do
        while true; do
            STATUS=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI --query 'NetworkInterfaces[0].Status' --output text)
            if [ "$STATUS" == "available" ]; then
                break
            fi
            echo "Waiting for network interface $ENI to be available for deletion..."
            sleep 10
        done
    done
}

# Terminate instances first to release network interfaces
terminate_instances

# Delete load balancers to release network interfaces
delete_load_balancers

# Detach and delete network interfaces (ENIs)
echo "Detaching and deleting network interfaces..."
ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
wait_for_network_interfaces "$ENIS"
for ENI in $ENIS; do
    ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text)
    if [ "$ATTACHMENT_ID" != "None" ]; then
        aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID
    fi
    aws ec2 delete-network-interface --network-interface-id $ENI
done

# Release Elastic IPs associated with NAT gateways
echo "Releasing Elastic IPs associated with NAT gateways..."
EIPS=$(aws ec2 describe-addresses --filters "Name=domain,Values=vpc" --query "Addresses[*].AllocationId" --output text)
for EIP in $EIPS; do
    aws ec2 release-address --allocation-id $EIP
done

# Delete NAT gateways
echo "Deleting NAT gateways..."
NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].NatGatewayId" --output text)
for NAT_GATEWAY in $NAT_GATEWAYS; do
    aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GATEWAY
done

# Wait for NAT gateways to be deleted
for NAT_GATEWAY in $NAT_GATEWAYS; do
    aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_GATEWAY
done

# Delete VPC endpoints
echo "Deleting VPC endpoints..."
VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text)
for ENDPOINT in $VPC_ENDPOINTS; do
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ENDPOINT
done

# Detach and delete internet gateways
echo "Detaching and deleting internet gateways..."
INTERNET_GATEWAYS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
for IGW in $INTERNET_GATEWAYS; do
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW
done

# Delete subnets
echo "Deleting subnets..."
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
for SUBNET in $SUBNETS; do
    aws ec2 delete-subnet --subnet-id $SUBNET
done

# Delete routes in route tables
echo "Deleting routes in route tables..."
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[*].RouteTableId" --output text)
for ROUTE_TABLE in $ROUTE_TABLES; do
    ROUTES=$(aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE --query "RouteTables[0].Routes[?DestinationCidrBlock != '10.0.0.0/16'].DestinationCidrBlock" --output text)
    for ROUTE in $ROUTES; do
        aws ec2 delete-route --route-table-id $ROUTE_TABLE --destination-cidr-block $ROUTE
    done
done

# Delete route tables (excluding the main one)
echo "Deleting route tables..."
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" --output text)
for ROUTE_TABLE in $ROUTE_TABLES; do
    aws ec2 delete-route-table --route-table-id $ROUTE_TABLE
done

# Delete VPC peering connections
echo "Deleting VPC peering connections..."
VPC_PEERING_CONNECTIONS=$(aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$VPC_ID" --query "VpcPeeringConnections[*].VpcPeeringConnectionId" --output text)
for PEERING_CONNECTION in $VPC_PEERING_CONNECTIONS; do
    aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PEERING_CONNECTION
done

# Delete security groups (excluding the default one)
echo "Deleting security groups..."
SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
for SECURITY_GROUP in $SECURITY_GROUPS; do
    # Revoke all ingress and egress rules
    INGRESS_RULES=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SECURITY_GROUP" --query "SecurityGroupRules[?IsEgress==\`false\`].{Protocol:IpProtocol,Port:FromPort,Cidr: CidrIpv4,GroupId:ReferencedGroupInfo.GroupId}" --output json)
    for rule in $(echo "${INGRESS_RULES}" | jq -c '.[]'); do
        PROTOCOL=$(echo "$rule" | jq -r '.Protocol')
        PORT=$(echo "$rule" | jq -r '.Port')
        CIDR=$(echo "$rule" | jq -r '.Cidr')
        GROUPID=$(echo "$rule" | jq -r '.GroupId')
        if [ "$CIDR" != "null" ]; then
            aws ec2 revoke-security-group-ingress --group-id $SECURITY_GROUP --protocol $PROTOCOL --port $PORT --cidr $CIDR
        elif [ "$GROUPID" != "null" ]; then
            aws ec2 revoke-security-group-ingress --group-id $SECURITY_GROUP --protocol $PROTOCOL --port $PORT --source-group $GROUPID
        fi
    done

    EGRESS_RULES=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SECURITY_GROUP" --query "SecurityGroupRules[?IsEgress==\`true\`].{Protocol:IpProtocol,Port:FromPort,Cidr: CidrIpv4,GroupId:ReferencedGroupInfo.GroupId}" --output json)
    for rule in $(echo "${EGRESS_RULES}" | jq -c '.[]'); do
        PROTOCOL=$(echo "$rule" | jq -r '.Protocol')
        PORT=$(echo "$rule" | jq -r '.Port')
        CIDR=$(echo "$rule" | jq -r '.Cidr')
        GROUPID=$(echo "$rule" | jq -r '.GroupId')
        if [ "$CIDR" != "null" ]; then
            aws ec2 revoke-security-group-egress --group-id $SECURITY_GROUP --protocol $PROTOCOL --port $PORT --cidr $CIDR
        elif [ "$GROUPID" != "null" ]; then
            aws ec2 revoke-security-group-egress --group-id $SECURITY_GROUP --protocol $PROTOCOL --port $PORT --destination-group $GROUPID
        fi
    done
    aws ec2 delete-security-group --group-id $SECURITY_GROUP
done

# Delete network ACLs (excluding the default one)
echo "Deleting network ACLs..."
NETWORK_ACLS=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkAcls[?IsDefault==\`false\`].NetworkAclId" --output text)
for ACL in $NETWORK_ACLS; do
    aws ec2 delete-network-acl --network-acl-id $ACL
done

# Delete the VPC
echo "Deleting the VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID

echo "VPC $VPC_ID and all associated resources have been deleted."

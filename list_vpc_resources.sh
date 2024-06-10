#!/bin/bash

# Set the AWS profile and region
export AWS_PROFILE=$1 # This sets the profile to use for the CLI commands or if you want change this to the profile you want to use but as is you must provide the profile as the first argument when running the script like this for example ./list_vpc_resources.sh myprofilename
export AWS_REGION=us-east-1

# Check if a VPC ID is provided
if [ -z "$2" ]; then
    echo "Usage: $0 <vpc-id>"
    exit 1
fi

VPC_ID=$2

echo "Listing resources associated with VPC: $VPC_ID"

# List EC2 instances
echo "Instances:"
aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query "Reservations[*].Instances[*].InstanceId" --output text

# List Network Interfaces
echo "Network Interfaces:"
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text

# List Subnets
echo "Subnets:"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text

# List Route Tables
echo "Route Tables:"
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[*].RouteTableId" --output text

# List Internet Gateways
echo "Internet Gateways:"
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text

# List NAT Gateways
echo "NAT Gateways:"
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].NatGatewayId" --output text

# List VPC Endpoints
echo "VPC Endpoints:"
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text

# List Security Groups
echo "Security Groups:"
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[*].GroupId" --output text

# List Network ACLs
echo "Network ACLs:"
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkAcls[*].NetworkAclId" --output text

# List Load Balancers
echo "Load Balancers:"
aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text

# List VPC Peering Connections
echo "VPC Peering Connections:"
aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$VPC_ID" --query "VpcPeeringConnections[*].VpcPeeringConnectionId" --output text

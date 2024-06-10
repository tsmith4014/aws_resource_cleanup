#!/bin/bash

# Set the AWS profile to use 
export AWS_PROFILE=$1 # This sets the profile to use for the CLI commands or if you want change this to the profile you want to use but as is you must provide the profile as the first argument when running the script like this for example ./find_vpc_creator.sh myprofilename
export AWS_REGION=us-west-2  # Specify the region of the VPCs

# Check if VPC IDs are provided
if [ -z "$2" ]; then
    echo "Usage: $0 <vpc-id1> <vpc-id2> ..."
    exit 1
fi

# Function to get VPC information
get_vpc_info() {
    VPC_ID=$2
    echo "Fetching information for VPC: $VPC_ID"

    # Get VPC details
    aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[*].{VpcId:VpcId,State:State,CidrBlock:CidrBlock,InstanceTenancy:InstanceTenancy,IsDefault:IsDefault,Tags:Tags}" --output table

    # Get associated resources
    echo "Associated Subnets:"
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].{SubnetId:SubnetId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone,State:State,Tags:Tags}" --output table
    
    echo "Associated Route Tables:"
    aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[*].{RouteTableId:RouteTableId,Routes:Routes,Associations:Associations,Tags:Tags}" --output table
    
    echo "Associated Internet Gateways:"
    aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].{InternetGatewayId:InternetGatewayId,Attachments:Attachments,Tags:Tags}" --output table
    
    echo "Associated NAT Gateways:"
    aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].{NatGatewayId:NatGatewayId,State:State,SubnetId:SubnetId,Tags:Tags}" --output table
    
    echo "Associated VPC Endpoints:"
    aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].{VpcEndpointId:VpcEndpointId,ServiceName:ServiceName,VpcEndpointType:VpcEndpointType,State:State,Tags:Tags}" --output table
    
    echo "Associated Security Groups:"
    aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName,Description:Description,Tags:Tags}" --output table
    
    echo "Associated Network ACLs:"
    aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkAcls[*].{NetworkAclId:NetworkAclId,Entries:Entries,Associations:Associations,Tags:Tags}" --output table
    
    echo "Associated Instances:"
    aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query "Reservations[*].Instances[*].{InstanceId:InstanceId,InstanceType:InstanceType,State:State,Tags:Tags}" --output table
    
    echo "Associated Load Balancers:"
    aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].{LoadBalancerArn:LoadBalancerArn,LoadBalancerName:LoadBalancerName,State:State,Type:Type,Tags:Tags}" --output table
}

# Iterate through all provided VPC IDs
for VPC_ID in "$@"; do
    get_vpc_info $VPC_ID
done

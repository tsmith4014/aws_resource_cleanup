#!/bin/bash

# Set the AWS profile to use 
export AWS_PROFILE=$1 # This sets the profile to use for the CLI commands or if you want change this to the profile you want to use but as is you must provide the profile as the first argument when running the script like this for example ./delete_non_default_vpcs.sh myprofilename
export AWS_REGION=us-east-1  # This sets a default region for CLI commands and this must be the region where the VPCs are located to delete resources

# Get all AWS regions
REGIONS=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)

for REGION in $REGIONS; do
    echo "Checking region: $REGION"
    # Fetch non-default VPCs
    VPCS=$(aws ec2 describe-vpcs --region $REGION --filters "Name=isDefault,Values=false" --query "Vpcs[*].VpcId" --output text)
    for VPC_ID in $VPCS; do
        echo "Deleting resources associated with VPC: $VPC_ID in region: $REGION"

        # Function to terminate instances in the VPC
        terminate_instances() {
            echo "Terminating instances in VPC: $VPC_ID in region: $REGION"
            INSTANCE_IDS=$(aws ec2 describe-instances --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "Reservations[*].Instances[*].InstanceId" --output text)
            if [ -n "$INSTANCE_IDS" ]; then
                aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_IDS
                aws ec2 wait instance-terminated --region $REGION --instance-ids $INSTANCE_IDS
            fi
        }

        # Function to delete load balancers in the VPC
        delete_load_balancers() {
            echo "Deleting load balancers in VPC: $VPC_ID in region: $REGION"
            LOAD_BALANCERS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text)
            for LB_ARN in $LOAD_BALANCERS; do
                echo "Deleting load balancer $LB_ARN..."
                aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn $LB_ARN
            done

            # Wait for load balancers to be deleted
            for LB_ARN in $LOAD_BALANCERS; do
                while true; do
                    LB_STATE=$(aws elbv2 describe-load-balancers --region $REGION --load-balancer-arns $LB_ARN --query "LoadBalancers[0].State.Code" --output text 2>&1)
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
                    STATUS=$(aws ec2 describe-network-interfaces --region $REGION --network-interface-ids $ENI --query 'NetworkInterfaces[0].Status' --output text)
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
        echo "Detaching and deleting network interfaces in VPC: $VPC_ID in region: $REGION"
        ENIS=$(aws ec2 describe-network-interfaces --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
        wait_for_network_interfaces "$ENIS"
        for ENI in $ENIS; do
            ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --region $REGION --network-interface-ids $ENI --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text)
            if [ "$ATTACHMENT_ID" != "None" ]; then
                aws ec2 detach-network-interface --region $REGION --attachment-id $ATTACHMENT_ID
            fi
            aws ec2 delete-network-interface --region $REGION --network-interface-id $ENI
        done

        # Release Elastic IPs associated with NAT gateways
        echo "Releasing Elastic IPs associated with NAT gateways in VPC: $VPC_ID in region: $REGION"
        EIPS=$(aws ec2 describe-addresses --region $REGION --filters "Name=domain,Values=vpc" --query "Addresses[*].AllocationId" --output text)
        for EIP in $EIPS; do
            aws ec2 release-address --region $REGION --allocation-id $EIP
        done

        # Delete NAT gateways
        echo "Deleting NAT gateways in VPC: $VPC_ID in region: $REGION"
        NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].NatGatewayId" --output text)
        for NAT_GATEWAY in $NAT_GATEWAYS; do
            aws ec2 delete-nat-gateway --region $REGION --nat-gateway-id $NAT_GATEWAY
        done

        # Wait for NAT gateways to be deleted
        for NAT_GATEWAY in $NAT_GATEWAYS; do
            aws ec2 wait nat-gateway-deleted --region $REGION --nat-gateway-ids $NAT_GATEWAY
        done

        # Delete VPC endpoints
        echo "Deleting VPC endpoints in VPC: $VPC_ID in region: $REGION"
        VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text)
        for ENDPOINT in $VPC_ENDPOINTS; do
            aws ec2 delete-vpc-endpoints --region $REGION --vpc-endpoint-ids $ENDPOINT
        done

        # Detach and delete internet gateways
        echo "Detaching and deleting internet gateways in VPC: $VPC_ID in region: $REGION"
        INTERNET_GATEWAYS=$(aws ec2 describe-internet-gateways --region $REGION --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
        for IGW in $INTERNET_GATEWAYS; do
            aws ec2 detach-internet-gateway --region $REGION --internet-gateway-id $IGW --vpc-id $VPC_ID
            aws ec2 delete-internet-gateway --region $REGION --internet-gateway-id $IGW
        done

        # Delete subnets
        echo "Deleting subnets in VPC: $VPC_ID in region: $REGION"
        SUBNETS=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
        for SUBNET in $SUBNETS; do
            aws ec2 delete-subnet --region $REGION --subnet-id $SUBNET
        done

        # Delete routes in route tables
        echo "Deleting routes in route tables in VPC: $VPC_ID in region: $REGION"
        ROUTE_TABLES=$(aws ec2 describe-route-tables --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[*].RouteTableId" --output text)
        for ROUTE_TABLE in $ROUTE_TABLES; do
            ROUTES=$(aws ec2 describe-route-tables --region $REGION --route-table-ids $ROUTE_TABLE --query "RouteTables[0].Routes[?DestinationCidrBlock != '10.0.0.0/16'].DestinationCidrBlock" --output text)
            for ROUTE in $ROUTES; do
                aws ec2 delete-route --region $REGION --route-table-id $ROUTE_TABLE --destination-cidr-block $ROUTE
            done
        done

        # Delete route tables (excluding the main one)
        echo "Deleting route tables in VPC: $VPC_ID in region: $REGION"
        ROUTE_TABLES=$(aws ec2 describe-route-tables --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" --output text)
        for ROUTE_TABLE in $ROUTE_TABLES; do
            aws ec2 delete-route-table --region $REGION --route-table-id $ROUTE_TABLE
        done


        # Delete VPC peering connections
        echo "Deleting VPC peering connections in VPC: $VPC_ID in region: $REGION"
        VPC_PEERING_CONNECTIONS=$(aws ec2 describe-vpc-peering-connections --region $REGION --filters "Name=requester-vpc-info.vpc-id,Values=$VPC_ID" --query "VpcPeeringConnections[*].VpcPeeringConnectionId" --output text)
        for PEERING_CONNECTION in $VPC_PEERING_CONNECTIONS; do
            aws ec2 delete-vpc-peering-connection --region $REGION --vpc-peering-connection-id $PEERING_CONNECTION
        done

        # Delete security groups (excluding the default one)
        echo "Deleting security groups in VPC: $VPC_ID in region: $REGION"
        SECURITY_GROUPS=$(aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
        for SECURITY_GROUP in $SECURITY_GROUPS; do
            # Revoke all ingress and egress rules
            INGRESS_RULES=$(aws ec2 describe-security-group-rules --region $REGION --filters "Name=group-id,Values=$SECURITY_GROUP" --query "SecurityGroupRules[?IsEgress==\`false\`].{Protocol:IpProtocol,Port:FromPort,Cidr: CidrIpv4,GroupId:ReferencedGroupInfo.GroupId}" --output json)
            for rule in $(echo "${INGRESS_RULES}" | jq -c '.[]'); do
                PROTOCOL=$(echo "$rule" | jq -r '.Protocol')
                PORT=$(echo "$rule" | jq -r '.Port')
                CIDR=$(echo "$rule" | jq -r '.Cidr')
                GROUPID=$(echo "$rule" | jq -r '.GroupId')
                if [ "$CIDR" != "null" ]; then
                    aws ec2 revoke-security-group-ingress --region $REGION --group-id $SECURITY_GROUP --protocol $PROTOCOL --port $PORT --cidr $CIDR
                elif [ "$GROUPID" != "null" ]; then
                    aws ec2 revoke-security-group-ingress --region $REGION --group-id $SECURITY_GROUP --protocol $PROTOCOL --port $PORT --source-group $GROUPID
                fi
            done

            EGRESS_RULES=$(aws ec2 describe-security-group-rules --region $REGION --filters "Name=group-id,Values=$SECURITY_GROUP" --query "SecurityGroupRules[?IsEgress==\`true\`].{Protocol:IpProtocol,Port:FromPort,Cidr: CidrIpv4,GroupId:ReferencedGroupInfo.GroupId}" --output json)
            for rule in $(echo "${EGRESS_RULES}" | jq -c '.[]'); do
                PROTOCOL=$(echo "$rule" | jq -r '.Protocol')
                PORT=$(echo "$rule" | jq -r '.Port')
                CIDR=$(echo "$rule" | jq -r '.Cidr')
                GROUPID=$(echo "$rule" | jq -r '.GroupId')
                if [ "$CIDR" != "null" ]; then
                    aws ec2 revoke-security-group-egress --region $REGION --group-id $SECURITY_GROUP --protocol $PROTOCOL --port $PORT --cidr $CIDR
                elif [ "$GROUPID" != "null" ]; then
                    aws ec2 revoke-security-group-egress --region $REGION --group-id $SECURITY_GROUP --protocol $PROTOCOL --port $PORT --destination-group $GROUPID
                fi
            done
            aws ec2 delete-security-group --region $REGION --group-id $SECURITY_GROUP
        done

        # Delete network ACLs (excluding the default one)
        echo "Deleting network ACLs in VPC: $VPC_ID in region: $REGION"
        NETWORK_ACLS=$(aws ec2 describe-network-acls --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkAcls[?IsDefault==\`false\`].NetworkAclId" --output text)
        for ACL in $NETWORK_ACLS; do
            aws ec2 delete-network-acl --region $REGION --network-acl-id $ACL
        done

        # Delete the VPC
        echo "Deleting the VPC $VPC_ID in region: $REGION"
        aws ec2 delete-vpc --region $REGION --vpc-id $VPC_ID

        echo "VPC $VPC_ID and all associated resources have been deleted in region $REGION."
        done
        done

        echo "All non-default VPCs and associated resources have been deleted."

# AWS Resource Cleanup Scripts

This repository contains a collection of shell scripts designed to manage and clean up AWS resources, specifically Virtual Private Clouds (VPCs) and their associated components. Below are the descriptions and usage instructions for each script.

## Scripts

1. **check_all_vpcs.sh**
2. **check_non_default_vpcs.sh**
3. **delete_non_default_vpcs.sh**
4. **delete_vpc_resources.sh**
5. **find_vpc_creator.sh**
6. **list_vpc_resources.sh**

### 1. check_all_vpcs.sh

**Description:**
This script lists all VPCs in all AWS regions.

**Usage:**

```bash
chmod +x check_all_vpcs.sh
./check_all_vpcs.sh <aws-profile>
```

**Example:**

```bash
chmod +x check_all_vpcs.sh
./check_all_vpcs.sh devopsbravo
```

### 2. check_non_default_vpcs.sh

**Description:**
This script lists all non-default VPCs in all AWS regions.

**Usage:**

```bash
chmod +x check_non_default_vpcs.sh
./check_non_default_vpcs.sh <aws-profile>
```

**Example:**

```bash
chmod +x check_non_default_vpcs.sh
./check_non_default_vpcs.sh devopsbravo
```

### 3. delete_non_default_vpcs.sh

**Description:**
This script deletes all non-default VPCs in all AWS regions.

**Usage:**

```bash
chmod +x delete_non_default_vpcs.sh
./delete_non_default_vpcs.sh <aws-profile>
```

**Example:**

```bash
chmod +x delete_non_default_vpcs.sh
./delete_non_default_vpcs.sh devopsbravo
```

### 4. delete_vpc_resources.sh

**Description:**
This script deletes all resources associated with a specified VPC and then deletes the VPC itself.  ***This works but will throw an error saying the VPC isnt found, because its been deleted....feel free to correct this :)

**Usage:**

```bash
chmod +x delete_vpc_resources.sh
./delete_vpc_resources.sh <aws-profile> <vpc-id>
```

**Parameters:**

- `<aws-profile>`: The AWS CLI profile to use.
- `<vpc-id>`: The ID of the VPC you want to delete.

**Example:**

```bash
chmod +x delete_vpc_resources.sh
./delete_vpc_resources.sh devopsbravo vpc-0abc1234def567890
```

### 5. find_vpc_creator.sh

**Description:**
This script attempts to find the IAM user who created the specified VPC.

**Usage:**

```bash
chmod +x find_vpc_creator.sh
./find_vpc_creator.sh <aws-profile> <vpc-id>
```

**Parameters:**

- `<aws-profile>`: The AWS CLI profile to use.
- `<vpc-id>`: The ID of the VPC whose creator you want to find.

**Example:**

```bash
chmod +x find_vpc_creator.sh
./find_vpc_creator.sh devopsbravo vpc-0abc1234def567890
```

### 6. list_vpc_resources.sh

**Description:**
This script lists all resources associated with a specified VPC.

**Usage:**

```bash
chmod +x list_vpc_resources.sh
./list_vpc_resources.sh <aws-profile> <vpc-id>
```

**Parameters:**

- `<aws-profile>`: The AWS CLI profile to use.
- `<vpc-id>`: The ID of the VPC whose resources you want to list.

**Example:**

```bash
chmod +x list_vpc_resources.sh
./list_vpc_resources.sh devopsbravo vpc-0abc1234def567890
```

## Prerequisites

- Ensure you have the AWS CLI installed and configured with appropriate credentials.
- Set the `AWS_PROFILE` and `AWS_REGION` environment variables as needed in each script.

## Setting Up AWS CLI

To install and configure AWS CLI, follow the official AWS documentation:
[Installing AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

To configure AWS CLI:

```bash
aws configure
```

## Note

- Make sure you have the necessary permissions to perform the operations these scripts execute.
- Review the scripts before running them in a production environment to avoid accidental deletion of critical resources.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

By following the above instructions, you should be able to effectively use the provided scripts for managing and cleaning up AWS resources.

---

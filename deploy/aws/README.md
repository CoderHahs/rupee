# Rupee on AWS

`rupee.yml` is a CloudFormation template for task 3.1a. It creates:

| Resource            | Setting                                                                                       |
| ------------------- | --------------------------------------------------------------------------------------------- |
| KMS key             | Customer-managed, yearly rotation, kept if the stack is deleted                               |
| EC2 instance        | `t4g.medium` (2 vCPUs, 4 GB), Ubuntu 24.04, IMDSv2 only                                       |
| EBS volumes         | Root (16 GiB) and data (40 GiB, mounted at `/var/lib/docker`), both encrypted with the key    |
| Security group      | No inbound rules. Members arrive over Tailscale, which only dials out                         |
| S3 bucket           | restic's repository: SSE-KMS with the key, public access blocked, HTTPS only, versioned, old versions kept 30 days |
| IAM role            | Lets the VM read and write the bucket, and allows Session Manager, so no SSH port is open     |

The data volume survives instance termination, and the key and bucket
survive stack deletion, so a mistake does not take the data with it.

## Steps

You need the AWS CLI signed in to your account, with the Session Manager
plugin, and a Tailscale account.

1. Create the stack (pick your region):

   ```sh
   aws cloudformation deploy --region <region> --stack-name rupee \
     --template-file deploy/aws/rupee.yml --capabilities CAPABILITY_IAM
   aws cloudformation describe-stacks --region <region> --stack-name rupee \
     --query "Stacks[0].Outputs" --output table
   ```

2. Open a shell on the VM without SSH:
   `aws ssm start-session --region <region> --target <InstanceId>`.
3. Join the tailnet: `sudo tailscale up --ssh`. After that you can also use
   `tailscale ssh ubuntu@<name>` from your own machine.
4. Enable MagicDNS and HTTPS certificates in the Tailscale admin console, and
   allow Funnel for this machine in the tailnet policy file.
5. Copy `deploy/` to the VM, for example with `git clone` of this repository.
6. Fill in `deploy/rupee.env` (see `rupee.env.example`):
   - `RESTIC_REPOSITORY` is the stack's `ResticRepository` output. Leave the
     `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` lines empty: restic
     uses the instance role, and `AWS_DEFAULT_REGION` is the stack's region.
   - `APP_DOMAIN` is the machine's MagicDNS name, `<name>.<tailnet>.ts.net`.
   - `RUPEE_IMAGE` is `ghcr.io/coderhahs/rupee:sha-<commit>` for a commit on
     `main`. If the GitHub package is private, run `docker login ghcr.io`
     with a token that can read packages, or make the package public.
7. Continue with "First deploy" in [`deploy/README.md`](../README.md),
   from step 3.

## Costs to expect

The instance, about 56 GiB of gp3 storage, the KMS key, the bucket and its
requests. A `t4g.medium` running all month is the largest part. Set an AWS
budget alert for the account before you start.

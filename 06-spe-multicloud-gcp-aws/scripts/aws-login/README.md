these two files run on the laptop, never on a VM. they exist because of one gap: the AWS CLI can sign in with `aws login`, but the AWS SDK inside packer and terraform cannot read that kind of session. without a bridge, every AWS command in this lesson would need long-lived access keys, which is exactly what we do not want on a laptop.

the bridge is a standard SDK feature turned inside out. the SDK knows how to fetch credentials from an HTTP endpoint when two environment variables point at it (`AWS_CONTAINER_CREDENTIALS_FULL_URI` and `AWS_CONTAINER_AUTHORIZATION_TOKEN`); that is how containers get their role credentials. `Invoke-WithAwsLogin.ps1` starts a tiny local server that plays that role, points the two variables at it, runs the command you asked for, and then shuts everything down and restores the environment.

~~~mermaid
flowchart LR
    U["you: aws login --profile default<br>(browser sign-in, short-lived session)"]
    W["Invoke-WithAwsLogin.ps1 <command>"]
    S["aws-login-credential-server.py<br>127.0.0.1, random port, random token"]
    C["packer / terraform<br>AWS SDK asks the endpoint for credentials"]
    X["aws configure export-credentials<br>fresh credentials from the login session"]
    U --> W --> S
    W -- "sets AWS_CONTAINER_* env, runs" --> C
    C -- "GET with token" --> S
    S -- "on every request" --> X
    X --> S --> C
~~~

what makes it safe enough for a laptop:

- **loopback only**, on a random port, and every request must carry a random token the wrapper generated for this one run. another process on the machine cannot guess it.
- **nothing is written to disk.** the server answers each request by running `aws configure export-credentials` on the spot and passing the result through. credentials live in memory for one command.
- **credentials refresh.** because every request re-exports, a packer build that runs longer than one credential lifetime keeps working.
- **it ends with the command.** the server is killed and the two variables are removed, so the next shell command is not silently talking through the bridge.

# where each file runs

| here | runs as | what it is |
|---|---|---|
| `Invoke-WithAwsLogin.ps1` | powershell, on the laptop | the wrapper. `Invoke-WithAwsLogin.ps1 <command> <args...>` with an optional `-AwsProfile`. finds python and the AWS CLI, starts the server, exports the two variables, runs the command, cleans up |
| `aws-login-credential-server.py` | python, started by the wrapper | the endpoint. `ThreadingHTTPServer` on `127.0.0.1`, checks the token, runs `aws configure export-credentials --profile <profile>`, returns access key, secret, session token and expiry as JSON |

# using it

sign in first, then wrap any packer or terraform command that touches AWS. GCP commands need no wrapper; application default credentials work directly.

~~~powershell
aws login --profile default
aws sts get-caller-identity --profile default

# from images/
& ..\scripts\aws-login\Invoke-WithAwsLogin.ps1 packer build '-only=spe.amazon-ebs.aws' '-var-file=variables.pkrvars.hcl' .

# from instances/aws/
& ..\..\scripts\aws-login\Invoke-WithAwsLogin.ps1 terraform plan
& ..\..\scripts\aws-login\Invoke-WithAwsLogin.ps1 terraform apply
~~~

if the login session has expired you will see `Your session has expired. Please reauthenticate using 'aws login'` from the first request; run `aws login` again and repeat the command. if your organisation gives you a normal profile based on an IAM role or IAM Identity Center, you can skip the wrapper and use that profile the usual way.

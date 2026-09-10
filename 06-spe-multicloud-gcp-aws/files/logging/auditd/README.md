auditd is the linux native logging framework.

it takes events collected by a kernel defined according to a set of rules that we define in:

- [50-spe.rules](50-spe.rules) Records execution attempts made by 64-bit and 32-bit programs
- [spe-tty-audit](spe-tty-audit) Records what users type or paste into their terminal sessions. Terminal recording is disabled for all other users.

then these events are sent to auditd writer who handles a physical file storing the logs in a special format that we can parse (we will look at this later). this phycical file with the raw audits can be configured using the file (TODO: if missing, create in this folder) called auditd.conf describing maximum size, rotation, etc.

# Most relevant raw auditd outputs:

TODO: show example of how the audit.log would look like with the most important fields
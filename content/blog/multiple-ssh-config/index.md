---
title: "Using multiple SSH configurations for git operations"
date: 2022-02-27T09:58:43+08:00
slug: ""
description: "Guide to setting up multiple SSH configurations for git operations"
keywords: ["git", "ssh", "guide"]
draft: false
tags: ["git", "ssh", "guide"]
math: false
toc: false
---

Some of you may be using multiple Github accounts and might have faced several permission related issues while setting up your SSH configuration to access private repositories from both accounts:
```
ERROR: Repository not found.
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

```
git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

I tried several solutions found all over the internet but all seems to missing some additional configuration to make it work as expected.

Eventually I figured out the neccessary configuration to make it work and thought it will be good to document it down for my future self.

---

# Working configuration

Let's say you have 2 SSH keys setup `id_ed25519_id1` and `id_ed25519_id2`.

```
# Account 1
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_id1
  IdentitiesOnly yes
# Account 2
Host personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_id2
  IdentitiesOnly yes
```

Now if you wish to clone a private repository from `Account 1`, run:
```
git clone git@github.com:account1/account1.github.io.git
```

For cloning a private repository from `Account 2`, run:
```
git clone git@personal:account2/account2.github.io.git
```

Take note that with this approach, the hostname of the `url` used has to be changed accordingly. 

---

# How does it work?

When we perform a `git clone` operation using SSH, `git` actually uses `ssh-agent` to perform `ssh`, and we can override the SSH command using `GIT_SSH_COMMAND` flag to increase the verbosity and see what happens under the hood.

```
GIT_SSH_COMMAND="ssh -v" git clone git@personal:account2/account2.github.io.git
```

Output:
```
Cloning into 'account2.github.io'...
OpenSSH_8.6p1, LibreSSL 2.8.3
debug1: Reading configuration data /Users/foo/.ssh/config
debug1: /Users/foo/.ssh/config line 6: Applying options for personal <----------------------------- found a matching Host from .ssh/config file
debug1: Reading configuration data /etc/ssh/ssh_config
debug1: /etc/ssh/ssh_config line 21: include /etc/ssh/ssh_config.d/* matched no files
debug1: /etc/ssh/ssh_config line 54: Applying options for *
debug1: Authenticator provider $SSH_SK_PROVIDER did not resolve; disabling
debug1: Connecting to github.com port 22.
debug1: Connection established.
debug1: identity file /Users/foo/.ssh/id_ed25519_id2 type 3 <------------------------------------------------ identified the identity file
debug1: identity file /Users/foo/.ssh/id_ed25519_id2-cert type -1 
debug1: Local version string SSH-2.0-OpenSSH_8.6
debug1: Remote protocol version 2.0, remote software version babeld-34bf8ec8
debug1: compat_banner: no match: babeld-34bf8ec8
debug1: Authenticating to github.com:22 as 'git'
debug1: load_hostkeys: fopen /Users/foo/.ssh/known_hosts2: No such file or directory
debug1: load_hostkeys: fopen /etc/ssh/ssh_known_hosts: No such file or directory
debug1: load_hostkeys: fopen /etc/ssh/ssh_known_hosts2: No such file or directory
debug1: SSH2_MSG_KEXINIT sent
debug1: SSH2_MSG_KEXINIT received
debug1: kex: algorithm: curve25519-sha256
debug1: kex: host key algorithm: ssh-ed25519
debug1: kex: server->client cipher: chacha20-poly1305@openssh.com MAC: <implicit> compression: none
debug1: kex: client->server cipher: chacha20-poly1305@openssh.com MAC: <implicit> compression: none
debug1: expecting SSH2_MSG_KEX_ECDH_REPLY
debug1: SSH2_MSG_KEX_ECDH_REPLY received
debug1: Server host key: ssh-ed25519 SHA256:xxxxxxx
debug1: load_hostkeys: fopen /Users/foo/.ssh/known_hosts2: No such file or directory
debug1: load_hostkeys: fopen /etc/ssh/ssh_known_hosts: No such file or directory
debug1: load_hostkeys: fopen /etc/ssh/ssh_known_hosts2: No such file or directory
debug1: Host 'github.com' is known and matches the ED25519 host key.
debug1: Found key in /Users/foo/.ssh/known_hosts:3
debug1: rekey out after 134217728 blocks
debug1: SSH2_MSG_NEWKEYS sent
debug1: expecting SSH2_MSG_NEWKEYS
debug1: SSH2_MSG_NEWKEYS received
debug1: rekey in after 134217728 blocks
debug1: Will attempt key: /Users/foo/.ssh/id_ed25519_id2 ED25519 SHA256:xxxx explicit <----------------------------- attempt to SSH using the identity file above
debug1: SSH2_MSG_EXT_INFO received
debug1: kex_input_ext_info: server-sig-algs=<ssh-ed25519-cert-v01@openssh.com,ecdsa-sha2-nistp521-cert-v01@openssh.com,ecdsa-sha2-nistp384-cert-v01@openssh.com,ecdsa-sha2-nistp256-cert-v01@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,sk-ecdsa-sha2-nistp256-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-256-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-dss-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ecdsa-sha2-nistp256@openssh.com,ssh-ed25519,ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256,ssh-rsa,ssh-dss>
debug1: SSH2_MSG_SERVICE_ACCEPT received
debug1: Authentications that can continue: publickey
debug1: Next authentication method: publickey
debug1: Offering public key: /Users/foo/.ssh/id_ed25519_id2 ED25519 SHA256:xxxx explicit <----------------------------------------- using the identity file above
debug1: Server accepts key: /Users/foo/.ssh/id_ed25519_id2 ED25519 SHA256:xxxx explicit
debug1: Authentication succeeded (publickey).
Authenticated to github.com ([20.205.243.166]:22).
debug1: channel 0: new [client-session]
debug1: Entering interactive session.
debug1: pledge: filesystem full
debug1: client_input_global_request: rtype hostkeys-00@openssh.com want_reply 0
debug1: client_input_hostkeys: searching /Users/foo/.ssh/known_hosts for github.com / (none)
debug1: client_input_hostkeys: searching /Users/foo/.ssh/known_hosts2 for github.com / (none)
debug1: client_input_hostkeys: hostkeys file /Users/foo/.ssh/known_hosts2 does not exist
debug1: client_input_hostkeys: no new or deprecated keys from server
debug1: Sending environment.
....
...
..
.
Transferred: sent 3664, received 190692 bytes, in 2.1 seconds
Bytes per second: sent 1735.8, received 90338.1
debug1: Exit status 0
Receiving objects: 100% (341/341), 172.98 KiB | 304.00 KiB/s, done.
Resolving deltas: 100% (127/127), done.
```

As annotated above, we can see how the identity file was selected based on the `Host` and used for cloning.

What happens if we use this configuration instead?
```
# Account 1
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_id1
  IdentitiesOnly yes
# Account 2
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_id2
  IdentitiesOnly yes
```

In this example, we set the same `Host` for both configurations.

Let's clone again account2's private repository again `GIT_SSH_COMMAND="ssh -v" git clone git@github:account2/account2.github.io.git`
```
Cloning into 'account2.github.io'...
OpenSSH_8.6p1, LibreSSL 2.8.3
debug1: Reading configuration data /Users/foo/.ssh/config
debug1: /Users/foo/.ssh/config line 1: Applying options for github.com <----------------------------- found 2 matching configurations based on Host
debug1: /Users/foo/.ssh/config line 6: Applying options for github.com
debug1: Reading configuration data /etc/ssh/ssh_config
debug1: /etc/ssh/ssh_config line 21: include /etc/ssh/ssh_config.d/* matched no files
debug1: /etc/ssh/ssh_config line 54: Applying options for *
debug1: Authenticator provider $SSH_SK_PROVIDER did not resolve; disabling
debug1: Connecting to github.com port 22.
debug1: Connection established.
debug1: identity file /Users/foo/.ssh/id_ed25519_id1 type 3 <------------------------------------------------ identified the identity files
debug1: identity file /Users/foo/.ssh/id_ed25519_id1-cert type -1
debug1: identity file /Users/foo/.ssh/id_ed25519_id2 type 3
debug1: identity file /Users/foo/.ssh/id_ed25519_id2-cert type -1
debug1: Local version string SSH-2.0-OpenSSH_8.6
debug1: Remote protocol version 2.0, remote software version babeld-34bf8ec8
debug1: compat_banner: no match: babeld-34bf8ec8
debug1: Authenticating to github.com:22 as 'git'
debug1: load_hostkeys: fopen /Users/foo/.ssh/known_hosts2: No such file or directory
debug1: load_hostkeys: fopen /etc/ssh/ssh_known_hosts: No such file or directory
debug1: load_hostkeys: fopen /etc/ssh/ssh_known_hosts2: No such file or directory
debug1: SSH2_MSG_KEXINIT sent
debug1: SSH2_MSG_KEXINIT received
debug1: kex: algorithm: curve25519-sha256
debug1: kex: host key algorithm: ssh-ed25519
debug1: kex: server->client cipher: chacha20-poly1305@openssh.com MAC: <implicit> compression: none
debug1: kex: client->server cipher: chacha20-poly1305@openssh.com MAC: <implicit> compression: none
debug1: expecting SSH2_MSG_KEX_ECDH_REPLY
debug1: SSH2_MSG_KEX_ECDH_REPLY received
debug1: Server host key: ssh-ed25519 SHA256:+xxxx
debug1: load_hostkeys: fopen /Users/foo/.ssh/known_hosts2: No such file or directory
debug1: load_hostkeys: fopen /etc/ssh/ssh_known_hosts: No such file or directory
debug1: load_hostkeys: fopen /etc/ssh/ssh_known_hosts2: No such file or directory
debug1: Host 'github.com' is known and matches the ED25519 host key.
debug1: Found key in /Users/foo/.ssh/known_hosts:3
debug1: rekey out after 134217728 blocks
debug1: SSH2_MSG_NEWKEYS sent
debug1: expecting SSH2_MSG_NEWKEYS
debug1: SSH2_MSG_NEWKEYS received
debug1: rekey in after 134217728 blocks
debug1: Will attempt key: /Users/foo/.ssh/id_ed25519_id1 ED25519 SHA256:xxxx explicit
debug1: Will attempt key: /Users/foo/.ssh/id_ed25519_id2 ED25519 SHA256:xxxx explicit
debug1: SSH2_MSG_EXT_INFO received
debug1: kex_input_ext_info: server-sig-algs=<ssh-ed25519-cert-v01@openssh.com,ecdsa-sha2-nistp521-cert-v01@openssh.com,ecdsa-sha2-nistp384-cert-v01@openssh.com,ecdsa-sha2-nistp256-cert-v01@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,sk-ecdsa-sha2-nistp256-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-256-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-dss-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ecdsa-sha2-nistp256@openssh.com,ssh-ed25519,ecdsa-sha2-nistp521,ecdsa-sha2-nistp384,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256,ssh-rsa,ssh-dss>
debug1: SSH2_MSG_SERVICE_ACCEPT received
debug1: Authentications that can continue: publickey
debug1: Next authentication method: publickey
debug1: Offering public key: /Users/foo/.ssh/id_ed25519_id1 ED25519 SHA256:xxxx explicit <------------------------------ despite matching 2 configurations, SSH defaulted to using the 1st match found
debug1: Server accepts key: /Users/foo/.ssh/id_ed25519_id1 ED25519 SHA256:xxxx explicit
debug1: Authentication succeeded (publickey).
Authenticated to github.com ([20.205.243.166]:22).
debug1: channel 0: new [client-session]
debug1: Entering interactive session.
debug1: pledge: filesystem full
debug1: client_input_global_request: rtype hostkeys-00@openssh.com want_reply 0
debug1: client_input_hostkeys: searching /Users/foo/.ssh/known_hosts for github.com / (none)
debug1: client_input_hostkeys: searching /Users/foo/.ssh/known_hosts2 for github.com / (none)
debug1: client_input_hostkeys: hostkeys file /Users/foo/.ssh/known_hosts2 does not exist
debug1: client_input_hostkeys: no new or deprecated keys from server
debug1: Sending environment.
....
...
..
.
ERROR: Repository not found.
debug1: channel 0: free: client-session, nchannels 1
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
debug1: fd 0 clearing O_NONBLOCK
Transferred: sent 2360, received 2416 bytes, in 0.6 seconds
Bytes per second: sent 4211.8, received 4311.8
debug1: Exit status 1
```

We can see that for this configuration, SSH will only use the first match found and you are out of luck if you want to clone using the second match.

---

There's probably a few other ways to do this, such as creating custom `git clone` alias to reference the respective identity files but this is one way that works for me.

Hope it helps whoever that is reading this.
# Setting up SSH with ED25519 key and diabling login with password

- Generate an ED25519 SSH key pair on a Windows client.
- Where to store the private key on Windows (client).
- Where to place the public key on an Ubuntu server (remote).
- Disable password authentication on the Ubuntu server to force key-only SSH logins.

Prerequisites and assumptions
- You have control of both the Windows client and the Ubuntu server.
- You can run commands as your Windows user and use `sudo` on the Ubuntu server.
- The server runs OpenSSH (`sshd`) — default on Ubuntu.

## 1. Generate an ED25519 key on Windows (client)

Open PowerShell and run the following command, replacing "Gamer" with [YourUserName], "Prime" with [YourPcName] and "beefy" with [RemoteServerName]:

```powershell
$ cd C:\Users\Gamer\.ssh\
$ ssh-keygen -t ed25519 -C "Gamer@Prime -> beefy" -f beefy
Generating public/private ed25519 key pair.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in beefy
Your public key has been saved in beefy.pub
The key fingerprint is:
SHA256:ZEpVpBpQt5S+pSx+LCKdhU1aEWVXK/Su+Q9IuZJ82CU Gamer@Prime -> beefy
The keys randomart image is:
+--[ED25519 256]--+
|-+*o.-+*o-+o.-+*o|
|-+*o.-+*o-+o.-+*o|
|-+*o.-+*o-+o.-+*o|
|-+*o.-+*o-+o.-+*o|
|-+*o.-+*o-+o.-+*o|
|-+*o.-+*o-+o.-+*o|
|-+*o.-+*o-+o.-+*o|
|-+*o.-+*o-+o.-+*o|
|-+*o.-+*o-+o.-+*o|
+----[SHA256]-----+
```

Notes:
- `-t ed25519` creates an Ed25519 keypair (modern, small, and secure).
- `-C "Gamer@Prime -> beefy"` sets the key's comment so you can identify it easily.
- `-f beefy` saves the private key to `C:\Users\Gamer\.ssh\beefy` and the public key to `beefy.pub`.

You'll be prompted for a passphrase — strongly recommended for improved security. If you prefer convenience over security, you can leave it empty. Kinda not the idea, if we go through the hassle of adding a keyfile...

## 2. Where to keep keys on Windows (client)

- Private key: `C:\Users\<your-windows-user>\.ssh\id_ed25519` — keep this file secret.
- Public key: `C:\Users\<your-windows-user>\.ssh\id_ed25519.pub` — safe to share with remote servers.

Best practices (PowerShell examples):

Set secure permissions on the `.ssh` folder:

```powershell
$ icacls $env:USERPROFILE\\.ssh /inheritance:r
$ icacls $env:USERPROFILE\\.ssh /grant:r "$($env:USERNAME):(R,W)"
```

Use the Windows OpenSSH agent to cache unlocked keys:

```powershell
$ Start-Service ssh-agent
$ ssh-add $env:USERPROFILE\\.ssh\\id_ed25519
```

## 3. Copy the public key to the Ubuntu server (remote)

Choose one of these methods.

a) Using `ssh-copy-id` (recommended if you have a Bash environment like WSL or Git Bash):

```bash
$ ssh-copy-id -i ~/.ssh/id_ed25519.pub user@your.server.ip
```

b) Manual copy (PowerShell + SSH)

1. Copy the public key to the clipboard (PowerShell):

Open the .pub file with VS Code or Notepad++ and copy all of it's conent. It should be quite small.

2. On the server (after logging in over SSH with your password), append it to `authorized_keys`:

```bash
$ mkdir -p ~/.ssh
$ chmod 700 ~/.ssh
$ sudo nano ~/.ssh/authorized_keys
$ chmod 600 ~/.ssh/authorized_keys
```

## 4. Verify key-based login

From your Windows client (PowerShell or WSL):

```powershell
$ ssh -i C:\Users\Gamer\.ssh\beefy buntu@beefy
```

You should now be logged in, ***without*** having to enter your password.

## 5. Disable password authentication on the Ubuntu server (force key-only login)

Important: Keep any working session open while you update `sshd_config` so you can revert if needed.

### a) Make a backup of the SSH configuration:

```bash
$ sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
```

### b) Edit `/etc/ssh/sshd_config` (for example with `nano` or `vim`) and ensure or add the following lines (uncomment if necessary):

```bash
$ sudo nano /etc/ssh/sshd_config
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
# It is recommended to disallow interactive root login
PermitRootLogin prohibit-password
```

### c) Test the config and restart `sshd`:

```bash
$ sudo sshd -t
$ sudo systemctl restart ssh
$ sudo systemctl status ssh --no-pager
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/usr/lib/systemd/system/ssh.service; disabled; preset: enabled)
     Active: active (running) since Sun 2025-09-14 22:53:33 UTC; 4s ago
TriggeredBy: ● ssh.socket
       Docs: man:sshd(8)
             man:sshd_config(5)
    Process: 4554 ExecStartPre=/usr/sbin/sshd -t (code=exited, status=0/SUCCESS)
   Main PID: 4557 (sshd)
      Tasks: 1 (limit: 76842)
     Memory: 1.2M (peak: 1.5M)
        CPU: 15ms
     CGroup: /system.slice/ssh.service
             └─4557 "sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups"

Sep 14 22:53:33 beefy systemd[1]: Starting ssh.service - OpenBSD Secure Shell server...
Sep 14 22:53:33 beefy sshd[4557]: Server listening on 0.0.0.0 port 22.
Sep 14 22:53:33 beefy sshd[4557]: Server listening on :: port 22.
Sep 14 22:53:33 beefy systemd[1]: Started ssh.service - OpenBSD Secure Shell server.
```

## 6. Optional: Restrict which users or keys can connect

- Use `AllowUsers` or `AllowGroups` in `sshd_config` to restrict who can log in:

```bash
$ sudo nano /etc/ssh/sshd_config
AllowUsers buntu
```

## 7. Tests the connection
Without sign off in the current PowerShell, open a new PowerShell window and try out your sign in without the password. Then try it out with the key file.

```PowerShell
$ ssh buntu@beefy
buntu@beefy: Permission denied (publickey).
$ ssh -i C:\Users\Gamer\.ssh\beefy buntu@beefy
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-79-generic x86_64)
```
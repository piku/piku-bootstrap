Bootstrap [Piku](https://github.com/piku/piku) onto a fresh Ubuntu server.

Piku lets you do `git push` deploys to your own server.

The easiest way to do this is using the get script:

```
ssh root@YOUR-FRESH-UBUNTU-SERVER
curl https://piku.github.io/get | sh
```

Or you can do the steps manually yourself:

```
ssh root@YOUR-FRESH-SERVER
curl -s https://raw.githubusercontent.com/piku/piku-bootstrap/master/piku-bootstrap > piku-bootstrap
chmod 755 piku-bootstrap
./piku-bootstrap first-run
```

Please use a fresh Ubuntu server as this script will modify system level settings.
See the playbooks if you want to see what will be changed.

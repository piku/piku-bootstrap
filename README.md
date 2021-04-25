Bootstrap [Piku](https://github.com/piku/piku) onto a new server.

The easiest way to do this is using the get script:

```
ssh root@YOUR-FRESH-SERVER
curl https://piku.github.io/get | sh
```

Or you can do the steps manually yourself:

```
ssh root@YOUR-FRESH-SERVER
curl -s https://raw.githubusercontent.com/piku/piku/master/piku-bootstrap > piku-bootstrap
chmod 755 piku-bootstrap
./piku-bootstrap first-run
```

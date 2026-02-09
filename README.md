Bootstrap [Piku](https://github.com/piku/piku) onto a fresh Ubuntu server. Piku lets you do `git push` deploys to your own server.

The easiest way to get started is using the get script:

```
ssh root@YOUR-FRESH-UBUNTU-SERVER
curl https://piku.github.io/get | sh
```

Or you can do the steps manually yourself:

```
ssh root@YOUR-FRESH-UBUNTU-SERVER
curl -s https://raw.githubusercontent.com/piku/piku-bootstrap/master/piku-bootstrap > piku-bootstrap
chmod 755 piku-bootstrap
./piku-bootstrap first-run
```

Use `./piku-bootstrap first-run --no-interactive` to suppress the first-run prompt, for example if you are running this in a provisioning script.

**Warning**: Please use a fresh Ubuntu server as this script will modify system level settings.
See [piku.yml](./playbooks/piku.yml) to see what will be changed.

The first time it is run `piku-bootstrap` will install itself into `/root/.piku-bootstrap` on the server and set up a virtualenv there with the dependencies it requires. It will only need to do this once.

The script will display a usage message and you can then bootstrap your server:

```shell
./piku-bootstrap install
```

Once you're done head over to the [Piku documentation](https://github.com/piku/piku/#using-piku) to see how to deploy your first app.

### Installing from a Fork

If you're developing piku or want to install from a custom fork, you can specify the repository and branch:

```shell
# Install from a different GitHub repository
./piku-bootstrap install --piku-repo=youruser/piku

# Install from a specific branch
./piku-bootstrap install --piku-branch=develop

# Install from a fork with a specific branch
./piku-bootstrap install --piku-repo=youruser/piku --piku-branch=feature-xyz
```

This is useful for:
- **Testing piku changes** on real servers before submitting PRs
- **Running your own fork** with custom modifications
- **Installing from development branches** like `develop` or feature branches

The options work with any playbook:

```shell
# Install postgres from your fork
./piku-bootstrap install postgres.yml --piku-repo=youruser/piku
```

### Installing other dependencies

`piku-bootstrap` uses Ansible internally and it comes with some extra built-in playbooks which you can use to bootstrap common components onto your `piku` server.

Use `piku-bootstrap list-playbooks` to show a list of built-in playbooks, and then to install one add it as an argument to the bootstrap command.

For example, to deploy `postgres` onto your server:

```shell
piku-bootstrap install postgres.yml
```

You can also use `piku-bootstrap` to run your own Ansible playbooks like this:

```shell
piku-bootstrap install ./myplaybook.yml
```

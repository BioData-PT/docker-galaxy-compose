# docker-galaxy-compose
A galaxy container optimised for docker compose or docker stack setups.

This container is a rewrite of the galaxy-k8s container with some changes to
make it better for compose setups, single container setups and galaxy testing.

Features:

+ All files that are generated when running galaxy are saved in one place:
  `/galaxy/data`.
+ A miniconda3 installlation is included. This means the machinery to install
  tools is already present.
+ http port exposed at 8080 and uwsgi port at 3031. This makes it possible to 
  talk to the container directly over http protocol, but also to use the faster
  uwsgi protocol in compose setups.

## Usage

### Container layout and ports

The container is based on [Debian](https://www.debian.org) and has the following
extra folders:

- `/galaxy`: The galaxy root folder
- `/galaxy/data`: Contains all user-generated data. 
- `/galaxy/server`: The galaxy server files (python files, static content etc.)
- `/galaxy/config`: Configuration files for galaxy
- `/galaxy/venv`: The galaxy virtual environment

Ports:

- `8080`: HTTP port. Can be used for direct access and usage as well as proxied
  trough NGINX.
- `3031`: UWSGI port. Can be used in combination with a NGINX proxy.

### Single container setup

For setting up galaxy on your own system.
+ To start using galaxy: 
```
docker run -it \
-v galaxy-data:/galaxy/data \
-p 8080:8080 \
-e GALAXY_CONFIG_ADMIN_USERS=myname@example.org \
biodatapt/galaxy-compose
```

This will create a running galaxy on http://localhost:8080. `myname@example`
will be the admin user. Any data created will be saved in the docker volume
`galaxy-data` so data and login persist across restarts.

### Compose setup

See the [compose-example](./compose_example).

# docker-galaxy-compose
A galaxy container optimised for docker compose or docker stack setups.

This container is a rewrite of the galaxy-k8s container with some changes to
make it better for compose setups, single container setups and galaxy testing:

+ All files that are generated when running galaxy are saved in one place:
  `/galaxy/data`.
+ A miniconda3 installlation is included. This means the machinery to install
  tools is already present.

## Usage

### Single container setup

For setting up galaxy on your own system.
+ To start using galaxy: 
```
docker run -it \
-v galaxy-data:/galaxy/data \
-p 8080:8080 \
-e GALAXY_CONFIG_ADMIN_USERS=myname@example.org \
lumc/galaxy-compose
```

This will create a running galaxy on http://localhost:8080. `myname@example`
will be the admin user. Any data created will be saved in the docker volume
`galaxy-data` so data and login persist across restarts.

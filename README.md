# Sarmat-ASK

This project is a migration of a legacy database system for automated warehouse. It was written for Oracle on PL/SQL and now it's rewritten for PostgreSQL on PL/pgSQL.

### Prerequisites

- docker / podman
- docker-compose

### Starting

During start all scripts from postgres-robots/postgres/ will be executed in alphabetical order.

```bash
docker-compose up --build
```

After that pgAdmin should be available at http://[::]:8080
Default credentials are specified in docker-compose.yml

### Stopping

There are no volumes for PostgreSQL specified, so any modifications will be lost after stop.

```bash
docker-compose down
```

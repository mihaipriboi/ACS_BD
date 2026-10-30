# Database Lab – University Politehnica of Bucharest (ACS)

This repository contains the laboratory assignments and projects for the Databases course at the Faculty of Automatic Control and Computers (ACS), University Politehnica of Bucharest.

## Contents
- Weekly lab work
- SQL scripts and example queries
- Helper scripts for running local SQL Server instances

## Technologies
- Microsoft SQL Server 2025 Express
- T-SQL
- Docker
- Bash

## Requirements
- Linux with Docker installed (`sudo pacman -S docker` on Arch)
- `mssql-tools18` (for `sqlcmd`), available from the AUR as `mssql-tools`
- About 2 GB of free RAM per running instance

Docker does not need to be enabled at boot. The scripts start it when needed.

## Scripts

### `sql-start.sh`
Shows a menu of your SQL Server instances, with each one's port and status. You can:
- **choose a number** to start that instance
- **press `n`** to create a new instance (you'll be asked for a name, a port and an SA password)
- **press `q`** to quit

```bash
./sql-start.sh
```

Each instance is fully separate: it has its own data, password and port. The first instance uses port `1433`, the next one `1434`, and so on, so several can run at once. Data is kept between restarts and reboots.

Instances never start automatically. Nothing runs until you start it.

### `sql-stop.sh`
Shows the running instances and lets you stop one, or all of them with `a`. Your data is kept.

```bash
./sql-stop.sh            # stop an instance
./sql-stop.sh --docker   # also shut down Docker afterwards
```

### Deleting an instance
This removes the instance and all of its data permanently:

```bash
docker rm mssql-<name> && docker volume rm mssql-<name>-data
```

## Connecting

Every instance uses the same connection details, apart from its port:

| Setting                  | Value                                       |
|--------------------------|---------------------------------------------|
| Host                     | `localhost`                                 |
| Port                     | shown in the `sql-start.sh` menu (e.g. `1433`) |
| Username                 | `sa`                                        |
| Password                 | the one you set when creating the instance  |
| Trust server certificate | **yes** (the instance uses a self-signed certificate) |

### From the terminal (`sqlcmd`)

```bash
sqlcmd -S localhost,1433 -U sa -C
```

SQL Server separates the host and port with a **comma**, not a colon. `-C` trusts the certificate. You'll be prompted for the password. Commands run when you type `GO`:

```sql
SELECT @@VERSION;
GO
```

### From VS Code
1. Install the **SQL Server (mssql)** extension.
2. Open the SQL Server view and add a new connection.
3. Server: `localhost,1433`, Authentication: SQL Login, User: `sa`, then your password.
4. Enable **Trust server certificate** when asked.

### From DBeaver
1. New Database Connection → **SQL Server**.
2. Host: `localhost`, Port: `1433`, Authentication: SQL Server Authentication, User: `sa`, then your password.
3. On the **Driver properties** tab, set `trustServerCertificate` to `true`.

## Notes
This repository is intended for educational use. Code and examples are provided to support learning and understanding of database concepts.

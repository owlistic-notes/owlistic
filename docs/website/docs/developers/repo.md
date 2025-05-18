---
sidebar_position: 3
---

# Repository Structure


## Directory Structure

The repository is organized into several directories to facilitate code organization and maintainability. Here's a breakdown of the main directories:

| Folder              | Description                                                                        |
| :------------------ | :--------------------------------------------------------------------------------- |
| `.github`           | Github repo templates and action workflows                                         |
| `src/backend`       | Source code for the mobile app                                                     |
| `src/frontend`      | Source code for the server app                                                     |
| `docs/diagrams`     | High level design diagrams for the project                                         |
| `docs/website`      | Source code for the [Owlistic website](https://owlistic-notes.github.io/owlistic/) |

### Server (Backend)

| Folder                   | Description                                        |
| :----------------------- | :--------------------------------------------------|
| `src/backend/cmd`        | Server main app                                    |
| `src/backend/config`     | Configuration files for the server app             |
| `src/backend/database`   | Database schema and operations                     |
| `src/backend/models`     | Data models used by the server app                 |
| `src/backend/middleware` | Middlewares used in the server app                 |
| `src/backend/routes`     | API routes for the server app                      |
| `src/backend/services`   | Business logic services for the server app         |
| `src/backend/broker`     | Message broker for handling requests and responses |
| `src/backend/utils`      | Utility functions for the server app               |


### App (Frontend)

| Folder                       | Description                                    |
| :--------------------------- | :--------------------------------------------- |
| `src/frontend/lib/core`      | Core functionality of the mobile app           |
| `src/frontend/lib/models`    | Data models used by the mobile app             |
| `src/frontend/lib/providers` | Providers for services used in the mobile app  |
| `src/frontend/lib/screens`   | Screens and layouts for the mobile app         |
| `src/frontend/lib/services`  | Business logic services for the mobile app     |
| `src/frontend/lib/viewmodel` | View models for the mobile app                 |
| `src/frontend/lib/widgets`   | Custom widgets used in the mobile app          |
| `src/frontend/lib/utils`     | Utility functions for the mobile app           |

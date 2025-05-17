---
sidebar_position: 3
---

# Repository Structure


## Directory Structure

The repository is organized into several directories to facilitate code organization and maintainability. Here's a breakdown of the main directories:

| Folder              | Description                                                                         |
| :------------------ | :---------------------------------------------------------------------------------- |
| `.github`           | Github repo templates and action workflows                                          |
| `src/backend`       | Source code for the mobile app                                                      |
| `src/frontend`      | Source code for the server app                                                      |
| `docs/diagrams`     | High level design diagrams for the project                                          |
| `docs/website`      | Source code for the [Owlistic website](https://owlistic-notes.github.io/owlistic/)  |

### Server

```text
src/backend/
├── cmd/main.go
├── config
├── database
├── models
├── middleware
├── routes
├── services
├── broker
└── utils
```

### App

```text
src/frontend/lib
├── main.dart
├── core
├── models
├── providers
├── screens
├── services
├── viewmodel
├── widgets
└── utils
```
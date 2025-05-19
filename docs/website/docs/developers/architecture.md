---
sidebar_position: 1
---

# Architecture

Owlistic uses a traditional client-server design, with a dedicated database for data persistence. On top of that, it leverages an event streaming system to push real-time updates to clients. Clients communicate with backend services over HTTP using REST APIs and listen over a websocket connection for server events. Below is a high level diagram of the architecture.

## High Level Design

![Architecture](/img/developers/architecture.png)

The diagram shows clients communicating with the server REST APIs for CRUD (Create, Read, Update, Delete) operations and listening to server events over a websocket connection.

The server exposes a gateway layer for REST APIs and a websocket connection. The API gateway is responsible for routing requests to the appropriate service, while the WebSocket gateway is responsible for and handling events.

Under the hood, the server communicates with downstream systems (i.e. Postgres, Kafka) through data models, both for data persistence and event streaming.

## Technology Stack

### Server

<img src="https://cdn.simpleicons.org/go" height="40" alt="go logo"/>
<img width="12" />
<img src="https://cdn.simpleicons.org/postgresql" height="40" alt="postgresql logo"/>
<img width="12" />
<img src="https://cdn.simpleicons.org/apachekafka" height="40" alt="kafka logo"/>
<img width="12" />

Owlistic backend is built using Go, a statically typed, compiled language. The main reason for choosing Go is its strong support for concurrency and efficient memory management, which are crucial for event-driven systems. It also uses the PostgreSQL database for data persistence and Apache Kafka as an event streaming system to push real-time updates to clients.

Please refer to the [Backend](developers/backend.md) section for more details.

### Client (Web/Mobile/Desktop App)

<img src="https://cdn.simpleicons.org/flutter" height="40" alt="flutter logo"/>
<img width="12" />
<img src="https://cdn.simpleicons.org/dart" height="40" alt="dart logo"/>
<img width="12" />

Owlistic client is built using Flutter, a popular open-source framework for building cross-platform applications. The client provides a user-friendly interface to interact with the backend and access the features of Owlistic. The main reason for choosing Flutter is its ease of use and ability to create cross-platforms mobile apps using the same codebase with minimal code changes.

Please refer to the [Frontend](developers/frontend.md) section for more details.

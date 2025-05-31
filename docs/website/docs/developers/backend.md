---
sidebar_position: 2
---

# Server

## Overview

Owlistic server is implemented following traditional client-server architecture exposing a set of REST APIs for Create, Update, Delete, Read (CRUD) operations. The server exposes a gateway layer for REST APIs responsible for routing requests to the appropriate service.

On top of that, Owlistic leverages event-driven architecture to push updates to an event broker system allowing fast and real-time synchronization. The server exposes a gateway layer for WebSocket connections responsible for pushing events from the downstream broker system to clients.

Following page provides a detailed overview of the server's components and their interactions.

## Design

Owlistic server is built using Go, a statically typed, compiled language. The main reason for choosing Go is its strong support for concurrency and efficient memory management, which are crucial for event-driven systems. It also uses the PostgreSQL database for data persistence and NATS as an event streaming system to push real-time updates to clients.

## Components

### API Routes

Owlistic server leverages a RESTful API architecture, providing endpoints for various CRUD operations. This section outlines the routes available for each CRUD operation.

The API routing mechanism is based on the [Gin](https://gin-gonic.com/) web framework, which provides a simple and intuitive way to define routes. Each route is defined using a combination of HTTP methods (GET, POST, PUT, DELETE) and URL paths and leverages [core services](#core-services) to handle requests and responses.

### Events Streaming

Owlistic server uses an event-driven architecture allowing for real-time updates and communication between services. This section explains how producers and consumers interact with its event streaming system.

#### Nats

The event streaming system is based on the [NATS](https://nats.io/) messaging system, which allows for efficient and scalable communication between services. Nats is a popular open-source messaging system that enables real-time communication between services. Owlistic server leverages NATS as an event streaming system, allowing for efficient and scalable communication between services.

#### Producer

The producer is responsible for publishing events to the event streaming system. It is implemented in `producer.go`.

* Responsible for publishing events to the NATS broker.
* Uses Go's built-in `nats` library for interacting with NATS.

#### Consumer

The consumer is responsible for consuming events from the event streaming system. It is implemented in `consumer.go`.

* Represented in code: `broker/consumer.go`
* Responsible for subscribing to events published by the producer and handling them accordingly.
* Uses Go's built-in `nats` library for interacting with NATS broker.

### Core Services

#### User Service
The User Service is responsible for managing user authentication and authorization. Its main responsibilities include:

* Handling user registration and login requests
* Authenticating users and verifying their credentials
* Authorizing users to access specific features and resources based on their roles and permissions
* Managing user profiles and settings

#### Notebook Service
The Notebook Service is responsible for managing [notebook entities](#notebook). Its main responsibilities include:

* Creating, reading, updating, and deleting notebooks
* Emitting events on notebook CRUD operations

:::note
Events emitted by notebook service are persisted as [event entities](#event) in a database table. At predefined time intervals the [event handler service](#event-handler-service) will process events not yet dispatched to forward them to the broker system.
:::

#### Note Service
The Note Service is responsible for managing [note entities](#note). Its main responsibilities include:

* Creating, reading, updating, and deleting (CRUD) notes
* Emitting events on note CRUD operations

:::note
Events emitted by note service are persisted as [event entities](#event) in a database table. At predefined time intervals the [event handler service](#event-handler-service) will process events not yet dispatched to forward them to the broker system.
:::

#### Block Service
Block Service is responsible for managing [block entities](#block). Its main responsibilities include:

* Creating, reading, updating, and deleting (CRUD) block entities
* Emitting events on block CRUD operations

:::note
Events emitted by block service are persisted as [event entities](#event) in a database table. At predefined time intervals the [event handler service](#event-handler-service) will process events not yet dispatched to forward them to the broker system.
:::

#### Task Service
The Task Service is responsible for managing [task entities](#task). Its main responsibilities include:

* Creating, reading, updating, and deleting tasks
* Emitting events on task CRUD operations

:::note
Events emitted by task service are persisted as [event entities](#event) in a database table. At predefined time intervals the [event handler service](#event-handler-service) will process events not yet dispatched to forward them to the broker system.
:::

### Event Streaming Services

#### Event Handler Service
The Event Handler Service is responsible for handling events generated by the system. It follows outbox design pattern and it is responsible for consuming un-dispatched events and forward them to the broker system. Its main responsibilities include:

* Processing events created on entitites CRUD operations
* Dispatching events to event broker system for further processing

#### WebSocket Service
The WebSocket Service is responsible for handling WebSocket connections with clients. Its main responsibilities include:

* Consuming events from all topics
* Establishing and maintaining WebSocket connections
* Handling incoming messages from clients
* Broadcasting messages to connected clients
* Managing connection states and closing connections as needed

#### Sync Service
The Sync Service is responsible for synchronizing data task and block entities. Its main responsibilities include:

* Consuming events from block and task topics
* Sync task entity on associated block entity changes
* Sync block entity on associated task entity changes

### Data Models

#### User Model

* Represented in code: `models/user.go`
* Description: A user is a entity that can create and interact with notebooks, notes, and tasks.
* Properties:
	+ ID: Unique identifier
	+ Email: Email address of the user
	+ PasswordHash: Hashed password of the user
	+ Username: Username chosen by the user
	+ DisplayName: Display name chosen by the user

#### Notebook

* Represented in code: `models/notebook.go`
* Description: A notebook is a container for notes.
* Properties:
	+ ID: Unique identifier
	+ UserID: Foreign key referencing the user who created it
	+ Name: Title of the notebook
	+ Description: Brief description of the notebook
	+ Notes: List of notes associated with this notebook

#### Note

* Represented in code: `models/note.go`
* Description: A note is a container for blocks and tags.
* Properties:
	+ ID: Unique identifier
	+ UserID: Foreign key referencing the user who created it
	+ NotebookID: Foreign key referencing the notebook that contains it
	+ Title: Title of the note
	+ Blocks: List of blocks associated with this note
	+ Tags: List of tags associated with this note

#### Block

* Represented in code: `models/block.go`
* Description: A block is a type of content that can be added to notes.
* Properties:
	+ ID: Unique identifier
	+ UserID: Foreign key referencing the user who created it
	+ NoteID: Foreign key referencing the note that contains it
	+ Type: Type of block (e.g., text, image)
    + Content: The actual content of the block
    + Metadata: Custom metadata set by the user

#### Task

* Represented in code: `models/task.go`
* Description: A task is a type of block.
* Properties:
	+ ID: Unique identifier
	+ UserID: Foreign key referencing the user who created it
	+ NoteID: Foreign key referencing the note that contains it
	+ Title: Title of the task
	+ Description: Brief description of the task
	+ IsCompleted: Flag indicating whether the task is completed
	+ DueDate: Due date of the task
	+ Metadata: Custom metadata set by the user

#### Event

* Represented in code: `models/event.go`
* Description: An event represents an action or occurrence that occurs within the system.
* Properties:
    + ID: Unique identifier for the event
    + Event: Name of the event (e.g., "note_created", "task_completed")
    + Entity: The entity associated with the event, such as a note or task
    + Timestamp: When the event occurred
    + Data: Additional data related to the event
    + Status: Current status of the event
# Evernote Clone

This is a project to build an Evernote-like application using the following stack:
- **Backend**: GoLang or Python
- **Database**: PostgreSQL
- **Streaming**: Kafka
- **Search**: Elasticsearch
- **Frontend**: React or any modern web framework

## Getting Started

### Prerequisites
- Docker and Docker Compose
- PostgreSQL
- Kafka
- Redis
- Node.js

### Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/evernote-clone.git
   cd evernote-clone
   ```

2. Start the services using Docker Compose:
   ```bash
   docker-compose up --build
   ```

3. Access the application:
   - Backend: `http://localhost:5000`
   - Frontend: `http://localhost:3000`

### Project Structure
```plaintext
owlistic-notes/owlistic/
├── backend/
├── frontend/
├── kafka/
├── postgres/
├── redis/
├── search/
└── docker-compose.yml
```

### Contributing
Feel free to open issues and submit pull requests.
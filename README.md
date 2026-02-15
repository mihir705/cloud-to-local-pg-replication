
# Cloud-to-Local PostgreSQL Logical Replication

## 📌 Overview

This project demonstrates production-style **logical replication** from a managed cloud PostgreSQL database (AWS RDS) to a local PostgreSQL instance running in Docker.

The goal is to ensure:

- Local DB stays in sync with cloud DB
- Replication automatically resumes after container restart
- Volume loss triggers automatic reseed
- No manual intervention required

---

# 🏗 Architecture Diagram (ASCII)

```
                ┌─────────────────────────────┐
                │     AWS RDS PostgreSQL      │
                │        (Publisher)          │
                │                             │
                │  Publication: pub_all_tables│
                │  Logical Replication ON     │
                └─────────────┬───────────────┘
                              │
                Logical Replication (WAL)
                              │
                              ▼
        ┌──────────────────────────────────────┐
        │      Docker Container (Local)        │
        │                                      │
        │   PostgreSQL Subscriber              │
        │   Subscription: sub_<id>             │
        │   Slot: slot_<id>                    │
        │                                      │
        │   Volumes:                           │
        │   - ./pgdata (DB data)               │
        │   - ./meta (subscriber_id)           │
        └──────────────────────────────────────┘
```

---

# ⚙️ Replication Method

**PostgreSQL Logical Replication (Pub/Sub)**

Chosen because:

- Near real-time replication
- Granular (table-level)
- Native to PostgreSQL
- Supported by AWS RDS
- Suitable for cross-environment replication

---

# 💾 Persistence Design

Two persistent directories:

## 1️⃣ pgdata
Stores PostgreSQL data directory.

Ensures:
- Container restarts do not lose data
- Subscription metadata persists

## 2️⃣ meta
Stores `subscriber_id`.

Ensures:
- Stable identity across rebuilds
- Stable replication slot naming
- No orphan slots on publisher

---

# 🔄 Restart Recovery

## Container Restart
- Data volume intact
- Subscription metadata intact
- Replication resumes automatically

## Container Recreate
- pgdata reused
- Replication continues

---

# 💥 Volume Loss Recovery (Reseed)

If `pgdata` is deleted:

1. Subscriber starts fresh
2. `subscriber_id` remains in `/meta`
3. Script checks if slot exists on publisher
4. Reuses slot if present
5. Performs `copy_data=true` reseed
6. Replication resumes

No manual action required.

---

# 🧠 Smart Slot Handling

Initialization script:

- Generates stable subscriber_id
- Derives slot + subscription names
- Checks publisher for existing slot
- Reuses slot if found
- Creates only if missing

Prevents:
- Orphan slots
- WAL bloat
- Manual cleanup

---

# 🧪 Testing Replication

## Insert in Cloud
```
INSERT INTO users(name) VALUES ('test');
```

## Verify Locally
```
SELECT * FROM users;
```

---

# 🧪 Test Recovery

## Restart Test
```
docker compose restart
```

Replication continues.

## Volume Loss Test
```
rm -rf pgdata
docker compose up -d
```

Local DB reseeds automatically.

---

# 🔐 Security Notes

- Replication user has least privileges
- SSL enabled for cloud connection
- Secrets not stored in Git

---

# 📂 Repository Structure

```
docker-compose.yml
env-sample.txt
docker/init/
meta/
README.md
```

---

# ✅ Outcome

- Fully automated replication
- Production-safe slot handling
- No manual recovery needed

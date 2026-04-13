# clean architectural design
made redis-server the msater
kept odilia-redi01 as the slaveof/replica of redis-server

# Sentinel container crashing
problem:
was read only
- ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf:ro

Solution:
made it writeable
- ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf

# Commands to verify roles

Check master (redis-server)

docker exec -it redis-server redis-cli INFO replication

Look for:
role:master
connected_slaves:1
A line like:
slave0:ip=odilia-redis01 (or your ip addr),port=6379,state=online,...

Check replica (odilia-redis01)
docker exec -it odilia-redis01 redis-cli INFO replication

Look for:
role:slave
master_host:redis-server
master_link_status:up

Check sentinel view of the master

docker exec -it odilia-redis-sentinel01 redis-cli -p 26379 SENTINEL masters

You should see a block for mymaster with:
name → mymaster
ip → redis-server
port → 6379
flags → master


# Compese file without DB replication
services:
  # -------------------------
  # YELB frontend + appserver
  # -------------------------
  yelb-ui:
    platform: linux/amd64
    image: mreferre/yelb-ui:0.7
    container_name: yelb-ui
    ports:
      - "80:80"
    depends_on:
      - yelb-appserver
    networks:
      - yelbnet
    restart: always

  yelb-appserver:
    platform: linux/amd64
    image: mreferre/yelb-appserver:0.5
    container_name: yelb-appserver
    depends_on:
      - yelb-db
      - redis-server
    environment:
      - YELB_DB_SERVER=yelb-db
      - YELB_REDIS_SERVER=redis-server
    networks:
      - yelbnet
    restart: always

  # ------------------------------
  # Redis HA cluster (master + replica)
  # ------------------------------
  redis-server:
    image: redis:4.0.2
    container_name: redis-server
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - redis-master-data:/data
      - ./redis/master/redis.conf:/usr/local/etc/redis/redis.conf:ro
    ports:
      - "6379:6379"
    networks:
      - yelbnet
    restart: always

  odilia-redis01:
    image: redis:4.0.2
    container_name: odilia-redis01
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - redis-replica-data:/data
      - ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf:ro
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # Redis Sentinels (3 nodes)
  # -------------------------
  odilia-redis-sentinel01:
    image: redis:4.0.2
    container_name: odilia-redis-sentinel01
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
    networks:
      - yelbnet
    ports:
      - "26379:26379"   # optional, handy for debugging from host
    restart: always

  odilia-redis-sentinel02:
    image: redis:4.0.2
    container_name: odilia-redis-sentinel02
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
    networks:
      - yelbnet
    restart: always

  odilia-redis-sentinel03:
    image: redis:4.0.2
    container_name: odilia-redis-sentinel03
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # YELB DB (main)
  # -------------------------
  yelb-db:
    platform: linux/amd64
    image: mreferre/yelb-db:0.5
    container_name: yelb-db
    networks:
      - yelbnet
    restart: always
    volumes:
      - db-data:/var/lib/postgresql/data

  # ------------------------------------------
  # Extra Postgres instances (not true replicas)
  # ------------------------------------------
  odilia-db-replication01:
    platform: linux/amd64
    image: mreferre/yelb-db:0.5
    container_name: yelb-db-replica1
    networks:
      - yelbnet
    restart: always
    volumes:
      - db-data1:/var/lib/postgresql/data

  odilia-db-replication02:
    platform: linux/amd64
    image: mreferre/yelb-db:0.5
    container_name: yelb-db-replica2
    networks:
      - yelbnet
    restart: always
    volumes:
      - db-data2:/var/lib/postgresql/data

  odilia-db-replication03:
    platform: linux/amd64
    image: mreferre/yelb-db:0.5
    container_name: yelb-db-replica3
    networks:
      - yelbnet
    restart: always
    volumes:
      - db-data3:/var/lib/postgresql/data

# -------------------------
# Network
# -------------------------
networks:
  yelbnet:
    driver: bridge

# -------------------------
# Volumes
# -------------------------
volumes:
  db-data:
  db-data1:
  db-data2:
  db-data3:
  redis-master-data:
  redis-replica-data:

#update

redis:4.0.2 was used for the original project
it does not allow replicaof, i had to use slaveof.


#==================================
ok
#==================================

services:
  # -------------------------
  # YELB frontend + appserver
  # -------------------------
  yelb-ui:
    platform: linux/amd64
    image: mreferre/yelb-ui:0.7
    container_name: yelb-ui
    ports:
      - "80:80"
    depends_on:
      - yelb-appserver
    networks:
      - yelbnet
    restart: always

  yelb-appserver:
    platform: linux/amd64
    image: mreferre/yelb-appserver:0.5
    container_name: yelb-appserver
    depends_on:
      - pg-haproxy
      - redis-haproxy 
    environment:
      - YELB_DB_SERVER=pg-haproxy
      - YELB_REDIS_SERVER=redis-haproxy 
    networks:
      - yelbnet
    restart: always

  # ------------------------------
  # Redis HA cluster (master + replica)
  # ------------------------------
  redis-server:
    image: redis:7.2
    container_name: redis-server
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - redis-master-data:/data
      - ./redis/master/redis.conf:/usr/local/etc/redis/redis.conf:ro
    # ports:
    #  - "6379:6379"
    networks:
      - yelbnet
    restart: always

  odilia-redis01:
    image: redis:7.2
    container_name: odilia-redis01
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - redis-replica-data:/data
      - ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf:ro
    networks:
      - yelbnet
    restart: always
  
  odilia-redis02:
    image: redis:7.2
    container_name: odilia-redis02
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - redis-replica2-data:/data
      - ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf:ro
    networks:
      - yelbnet
    restart: always


  # -------------------------
  # Redis Sentinels (3 nodes)
  # -------------------------
  odilia-redis-sentinel01:
    image: redis:7.2
    container_name: odilia-redis-sentinel01
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel-01.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
      - odilia-redis02
    networks:
      - yelbnet
    ports:
      - "26379:26379"
    restart: always

  odilia-redis-sentinel02:
    image: redis:7.2
    container_name: odilia-redis-sentinel02
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel-02.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
      - odilia-redis02
    networks:
      - yelbnet
    restart: always

  odilia-redis-sentinel03:
    image: redis:7.2
    container_name: odilia-redis-sentinel03
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel-03.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
      - odilia-redis02
    networks:
      - yelbnet
    restart: always

  # ------------------------------
  # YELB DB (PRIMARY) - Postgres 14
  # -------------------------------
  yelb-db:
    image: postgres:14
    container_name: yelb-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres_password
      POSTGRES_HOST_AUTH_METHOD: trust
    command: >
      postgres
      -c wal_level=replica
      -c max_wal_senders=10
      -c max_replication_slots=10
      -c hot_standby=on
      -c listen_addresses='*'
    volumes:
      - db-data:/var/lib/postgresql/data
      - ./yelb-db/init-yelb-db.sh:/docker-entrypoint-initdb.d/01-init-yelb-db.sh:ro
      - ./yelb-db/02-create-replicator.sql:/docker-entrypoint-initdb.d/02-create-replicator.sql:ro
      - ./yelb-db/03-pghba-override.sh:/docker-entrypoint-initdb.d/03-pghba-override.sh:ro  # 👈 NEW
    networks:
      - yelbnet
    restart: always


  # ------------------------------------------
  # Postgres streaming replicas
  # ------------------------------------------
  odilia-db-replication01:
    image: postgres:14
    container_name: yelb-db-replica1
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres_password
      POSTGRES_HOST_AUTH_METHOD: trust
      PGPASSWORD: replicatorpass 
    depends_on:
      - yelb-db
    entrypoint: ["/usr/local/bin/replica-entrypoint.sh"]
    volumes:
      - db-data1:/var/lib/postgresql/data
      - ./postgres/replica-entrypoint.sh:/usr/local/bin/replica-entrypoint.sh:ro
    networks:
      - yelbnet
    restart: always

  odilia-db-replication02:
    image: postgres:14
    container_name: yelb-db-replica2
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres_password
      POSTGRES_HOST_AUTH_METHOD: trust
      PGPASSWORD: replicatorpass 
    depends_on:
      - yelb-db
    entrypoint: ["/usr/local/bin/replica-entrypoint.sh"]
    volumes:
      - db-data2:/var/lib/postgresql/data
      - ./postgres/replica-entrypoint.sh:/usr/local/bin/replica-entrypoint.sh:ro
    networks:
      - yelbnet
    restart: always

  odilia-db-replication03:
    image: postgres:14
    container_name: yelb-db-replica3
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres_password
      POSTGRES_HOST_AUTH_METHOD: trust
      PGPASSWORD: replicatorpass 
    depends_on:
      - yelb-db
    entrypoint: ["/usr/local/bin/replica-entrypoint.sh"]
    volumes:
      - db-data3:/var/lib/postgresql/data
      - ./postgres/replica-entrypoint.sh:/usr/local/bin/replica-entrypoint.sh:ro
    networks:
      - yelbnet
    restart: always
  # ------------------------------
  # HAProxy for Postgres routing
  # ------------------------------
  pg-haproxy:
    image: haproxy:2.9
    container_name: pg-haproxy
    depends_on:
      - yelb-db
      - odilia-db-replication01
      - odilia-db-replication02
      - odilia-db-replication03
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    ports:
      - "5432:5432"      # expose Postgres via HAProxy on your host
    networks:
      - yelbnet
    restart: always

  # ------------------------------
  # HAProxy for Redis routing
  # ------------------------------
  redis-haproxy:
    image: haproxy:2.9
    container_name: redis-haproxy
    depends_on:
      - redis-server
      - odilia-redis01
      - odilia-redis02
    volumes:
      - ./haproxy/haproxy-redis.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    ports:
      - "6379:6379"   # optional: expose to host; not strictly needed for Yelb
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # Metrics exporters
  # -------------------------
  postgres-exporter:
    image: quay.io/prometheuscommunity/postgres-exporter
    container_name: postgres-exporter
    environment:
      # DSN to the PRIMARY Postgres
      - DATA_SOURCE_NAME=postgresql://postgres:postgres_password@yelb-db:5432/postgres?sslmode=disable
    networks:
      - yelbnet
    restart: always

  redis-exporter:
    image: oliver006/redis_exporter:v1.61.0
    container_name: redis-exporter
    command:
      - "--redis.addr=redis-haproxy:6379"
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # Prometheus (metrics DB)
  # -------------------------
  prometheus:
    image: prom/prometheus:v2.55.0
    container_name: prometheus
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--web.enable-lifecycle"
    ports:
      - "9090:9090"
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # Grafana (dashboards)
  # -------------------------
  grafana:
    image: grafana/grafana:11.0.0
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./monitoring/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources
    networks:
      - yelbnet
    restart: always

# -------------------------
# Network
# -------------------------
networks:
  yelbnet:
    driver: bridge

# -------------------------
# Volumes
# -------------------------
volumes:
  db-data:
  db-data1:
  db-data2:
  db-data3:
  redis-master-data:
  redis-replica-data:
  redis-replica2-data:
  grafana-data:

#==================================
fully HA tested and working
#==================================

services:
  # -------------------------
  # YELB frontend + appserver
  # -------------------------
  yelb-ui:
    platform: linux/amd64
    image: mreferre/yelb-ui:0.7
    container_name: yelb-ui
    ports:
      - "80:80"
    depends_on:
      - yelb-appserver
    networks:
      - yelbnet
    restart: always

  yelb-appserver:
    platform: linux/amd64
    image: eseosaiyangbe/yelb-appserver:v1   # <--- UPDATED: my custom image
    container_name: yelb-appserver
    depends_on:
      - pg-haproxy
      - redis-haproxy 
    environment:
      - YELB_DB_SERVER=pg-haproxy                  # <--- appserver reads this (production/test/custom)
      - YELB_REDIS_SERVER=redis-haproxy           # <--- appserver reads this
      # Later, when you enable Redis auth:
      # - REDIS_PASSWORD=yourStrongPassword
    networks:
      - yelbnet
    restart: always

  # ------------------------------
  # Redis HA cluster (master + replicas)
  # ------------------------------
  redis-server:
    image: redis:7.2
    container_name: redis-server
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - redis-master-data:/data
      - ./redis/master/redis.conf:/usr/local/etc/redis/redis.conf:ro
    # ports:
    #  - "6379:6379"   # not needed; HAProxy fronts Redis
    networks:
      - yelbnet
    restart: always

  odilia-redis01:
    image: redis:7.2
    container_name: odilia-redis01
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - redis-replica-data:/data
      - ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf:ro
    networks:
      - yelbnet
    restart: always
  
  odilia-redis02:
    image: redis:7.2
    container_name: odilia-redis02
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - redis-replica2-data:/data
      - ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf:ro
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # Redis Sentinels (3 nodes)
  # -------------------------
  odilia-redis-sentinel01:
    image: redis:7.2
    container_name: odilia-redis-sentinel01
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel-01.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
      - odilia-redis02
    networks:
      - yelbnet
    ports:
      - "26379:26379"
    restart: always

  odilia-redis-sentinel02:
    image: redis:7.2
    container_name: odilia-redis-sentinel02
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel-02.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
      - odilia-redis02
    networks:
      - yelbnet
    restart: always

  odilia-redis-sentinel03:
    image: redis:7.2
    container_name: odilia-redis-sentinel03
    command: ["redis-sentinel", "/usr/local/etc/redis/sentinel.conf"]
    volumes:
      - ./sentinel/sentinel-03.conf:/usr/local/etc/redis/sentinel.conf
    depends_on:
      - redis-server
      - odilia-redis01
      - odilia-redis02
    networks:
      - yelbnet
    restart: always

  # ------------------------------
  # YELB DB (PRIMARY) - Postgres 14
  # -------------------------------
  yelb-db:
    image: postgres:14
    container_name: yelb-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres_password
      POSTGRES_HOST_AUTH_METHOD: trust
    command: >
      postgres
      -c wal_level=replica
      -c max_wal_senders=10
      -c max_replication_slots=10
      -c hot_standby=on
      -c listen_addresses='*'
    volumes:
      - db-data:/var/lib/postgresql/data
      - ./yelb-db/init-yelb-db.sh:/docker-entrypoint-initdb.d/01-init-yelb-db.sh:ro
      - ./yelb-db/02-create-replicator.sql:/docker-entrypoint-initdb.d/02-create-replicator.sql:ro
      - ./yelb-db/03-pghba-override.sh:/docker-entrypoint-initdb.d/03-pghba-override.sh:ro
    networks:
      - yelbnet
    restart: always

  # ------------------------------------------
  # Postgres streaming replicas
  # ------------------------------------------
  odilia-db-replication01:
    image: postgres:14
    container_name: yelb-db-replica1
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres_password
      POSTGRES_HOST_AUTH_METHOD: trust
      PGPASSWORD: replicatorpass 
    depends_on:
      - yelb-db
    entrypoint: ["/usr/local/bin/replica-entrypoint.sh"]
    volumes:
      - db-data1:/var/lib/postgresql/data
      - ./postgres/replica-entrypoint.sh:/usr/local/bin/replica-entrypoint.sh:ro
    networks:
      - yelbnet
    restart: always

  odilia-db-replication02:
    image: postgres:14
    container_name: yelb-db-replica2
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres_password
      POSTGRES_HOST_AUTH_METHOD: trust
      PGPASSWORD: replicatorpass 
    depends_on:
      - yelb-db
    entrypoint: ["/usr/local/bin/replica-entrypoint.sh"]
    volumes:
      - db-data2:/var/lib/postgresql/data
      - ./postgres/replica-entrypoint.sh:/usr/local/bin/replica-entrypoint.sh:ro
    networks:
      - yelbnet
    restart: always

  odilia-db-replication03:
    image: postgres:14
    container_name: yelb-db-replica3
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres_password
      POSTGRES_HOST_AUTH_METHOD: trust
      PGPASSWORD: replicatorpass 
    depends_on:
      - yelb-db
    entrypoint: ["/usr/local/bin/replica-entrypoint.sh"]
    volumes:
      - db-data3:/var/lib/postgresql/data
      - ./postgres/replica-entrypoint.sh:/usr/local/bin/replica-entrypoint.sh:ro
    networks:
      - yelbnet
    restart: always

  # ------------------------------
  # HAProxy for Postgres routing
  # ------------------------------
  pg-haproxy:
    image: haproxy:2.9
    container_name: pg-haproxy
    depends_on:
      - yelb-db
      - odilia-db-replication01
      - odilia-db-replication02
      - odilia-db-replication03
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    ports:
      - "5432:5432"      # expose Postgres via HAProxy on your host
    networks:
      - yelbnet
    restart: always

  # ------------------------------
  # HAProxy for Redis routing
  # ------------------------------
  redis-haproxy:
    image: haproxy:2.9
    container_name: redis-haproxy
    depends_on:
      - redis-server
      - odilia-redis01
      - odilia-redis02
    volumes:
      - ./haproxy/haproxy-redis.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    ports:
      - "6379:6379"   # optional; Yelb only needs internal: redis-haproxy:6379
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # Metrics exporters
  # -------------------------
  postgres-exporter:
    image: quay.io/prometheuscommunity/postgres-exporter
    container_name: postgres-exporter
    environment:
      # Point exporter at the HAProxy VIP, not raw primary
      - DATA_SOURCE_NAME=postgresql://postgres:postgres_password@pg-haproxy:5432/postgres?sslmode=disable
    networks:
      - yelbnet
    restart: always

  redis-exporter:
    image: oliver006/redis_exporter:v1.61.0
    container_name: redis-exporter
    command:
      - "--redis.addr=redis-haproxy:6379"
      # When you add Redis auth later:
      # - "--redis.password=yourStrongPassword"
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # Prometheus (metrics DB)
  # -------------------------
  prometheus:
    image: prom/prometheus:v2.55.0
    container_name: prometheus
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--web.enable-lifecycle"
    ports:
      - "9090:9090"
    networks:
      - yelbnet
    restart: always

  # -------------------------
  # Grafana (dashboards)
  # -------------------------
  grafana:
    image: grafana/grafana:11.0.0
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./monitoring/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources
    networks:
      - yelbnet
    restart: always

# -------------------------
# Network
# -------------------------
networks:
  yelbnet:
    driver: bridge

# -------------------------
# Volumes
# -------------------------
volumes:
  db-data:
  db-data1:
  db-data2:
  db-data3:
  redis-master-data:
  redis-replica-data:
  redis-replica2-data:
  grafana-data:


NB:

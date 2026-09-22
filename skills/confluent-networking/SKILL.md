---
name: confluent-networking
description: Confluent Cloud and Confluent Platform networking reference — `confluent network` CLI (peering, PrivateLink, access points, DNS forwarders, gateways, static egress IPs, cluster links), broker listener patterns (listeners / advertised.listeners / listener.security.protocol.map, SASL_SSL), Confluent for Kubernetes external access (loadBalancer, nodePort, staticForHostBasedRouting) and broker DNS mapping, and Schema Registry endpoints. Use when configuring or debugging Kafka/Confluent connectivity.
---

## Confluent CLI Quick Reference

```bash
# Confluent Cloud networking
confluent network list
confluent network create --cloud aws --region us-east-1 --cidr 10.10.0.0/16
confluent network peering create --name my-peering --network <id> --cloud aws --account <aws-account-id> --vpc <vpc-id> --routes 10.0.0.0/8
confluent network peering list
confluent network peering describe <id>

# Private Link (AWS PrivateLink / GCP PSC / Azure Private Link)
confluent network private-link access create --name <name> --network <id> --aws-account <account-id>
confluent network private-link attachment list
confluent network private-link attachment connection list

# DNS forwarders (resolve on-prem/VPC DNS inside Confluent)
confluent network dns forwarder create --name <name> --network <id> --domains example.com --dns-server-ips 10.0.0.2
confluent network dns forwarder list
confluent network dns record create --name <name> --network <id> --domain kafka.internal --record A --value 10.0.1.5

# Gateways (egress/transit)
confluent network gateway create --name <name> --type EGRESS_PRIVATELINK_GATEWAY --cloud aws --region us-east-1
confluent network gateway list

# Access points (PrivateLink endpoint services, Private Network Interfaces)
confluent network access-point private-network-interface list

# IP addresses (static egress IPs)
confluent network ip-address list

# Network links (cross-environment/cluster connectivity)
confluent network link service create --name <name> --network <id>
confluent network link endpoint create --name <name> --network <id> --link-service <id>

# Schema Registry endpoints
confluent schema-registry endpoint list
confluent schema-registry cluster describe

# Environment / cluster context
confluent environment list
confluent environment use <id>
confluent kafka cluster list
confluent kafka cluster describe <id>  # shows bootstrap endpoint
confluent kafka client-config create java  # generates connection config
```

## Confluent Broker Listener Patterns

```properties
# Multi-listener setup (internal + external + replication)
listeners=INTERNAL://0.0.0.0:9092,EXTERNAL://0.0.0.0:9093,BROKER://0.0.0.0:9091
advertised.listeners=INTERNAL://broker1.internal:9092,EXTERNAL://broker1.example.com:9093,BROKER://broker1.internal:9091
listener.security.protocol.map=INTERNAL:SASL_SSL,EXTERNAL:SASL_SSL,BROKER:SASL_SSL,CONTROLLER:SASL_SSL

# Confluent Cloud client config (copy from: confluent kafka client-config create)
bootstrap.servers=<cluster>.confluent.cloud:9092
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
  username="<api-key>" password="<api-secret>";
client.dns.lookup=use_all_dns_ips
session.timeout.ms=45000
acks=all

# Schema Registry with auth
schema.registry.url=https://<sr-endpoint>
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=<sr-api-key>:<sr-api-secret>
```

## Confluent for Kubernetes (CFK) External Access

```yaml
# LoadBalancer (NLB per broker)
spec:
  listeners:
    external:
      externalAccess:
        type: loadBalancer
        loadBalancer:
          domain: kafka.example.com
          annotations:
            service.beta.kubernetes.io/aws-load-balancer-type: "external"
            service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
      tls:
        enabled: true

# Ingress / host-based routing (single LB for all brokers)
spec:
  listeners:
    external:
      externalAccess:
        type: staticForHostBasedRouting
        staticForHostBasedRouting:
          domain: kafka.example.com
          port: 443
      tls:
        enabled: true
# Required DNS records:
# kafka.example.com  -> ingress LB IP
# b0.example.com     -> ingress LB IP
# b1.example.com     -> ingress LB IP
# connect.example.com, ksqldb.example.com, controlcenter.example.com -> ingress LB IP

# NodePort
spec:
  listeners:
    external:
      externalAccess:
        type: nodePort
        nodePort:
          host: <node-hostname-or-lb>
          nodePortOffset: 30000
```

## Troubleshooting Workflow
1. Identify the symptom (timeout, connection refused, DNS failure, packet loss)
2. Isolate the layer: DNS -> routing -> security groups -> application
3. Use targeted tools: `dig` for DNS, `traceroute/mtr` for routing, `curl -v` for HTTP, `nc -zv` for port checks
4. Check security groups and NACLs (both inbound AND outbound rules)
5. Verify VPC route tables and peering/TGW routes
6. Document findings and resolution

### Confluent-Specific Troubleshooting
```bash
# Verify bootstrap server reachability (port 9092 for Confluent Cloud)
nc -zv <bootstrap-server> 9092
openssl s_client -connect <bootstrap-server>:9092 -servername <bootstrap-server>

# DNS: each broker gets its own hostname -- must all resolve
dig b0.<cluster>.confluent.cloud
dig b1.<cluster>.confluent.cloud

# Test auth separately from connectivity
confluent kafka topic list --cluster <id>

# CFK: check listener services per broker
kubectl get svc -n confluent -l component=kafka
kubectl describe svc kafka-0-lb -n confluent  # check LB ingress IP

# Confluent Platform: verify advertised.listeners match what clients see
kafka-broker-api-versions.sh --bootstrap-server broker1:9092 --command-config client.properties
```

## Shared Context
Read `.claude/agent-context/lead.md` for plan. Write findings to `.claude/agent-context/networking.md`.
Create the `.claude/agent-context/` directory if it doesn't exist.

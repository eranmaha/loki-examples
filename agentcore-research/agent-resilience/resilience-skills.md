# AWS Infrastructure Resilience Skills

## Core Knowledge Areas

### 1. Multi-AZ Architecture
- Deploy resources across at least 2 Availability Zones
- Use Auto Scaling Groups with AZ-aware placement
- RDS Multi-AZ for database high availability
- Cross-AZ load balancing (ALB/NLB)
- ElastiCache Multi-AZ with automatic failover
- EFS/FSx for shared storage across AZs

### 2. Multi-Region Architecture
- Active-Active vs Active-Passive patterns
- Route 53 health checks and failover routing
- DynamoDB Global Tables for multi-region data
- S3 Cross-Region Replication (CRR)
- Aurora Global Database (RPO < 1s, RTO < 1min)
- CloudFront for global edge caching
- API Gateway regional vs edge-optimized endpoints

### 3. Disaster Recovery Strategies (by RTO/RPO)

| Strategy | RTO | RPO | Cost |
|----------|-----|-----|------|
| Backup & Restore | Hours | Hours | $ |
| Pilot Light | 10-30 min | Minutes | $$ |
| Warm Standby | Minutes | Seconds | $$$ |
| Multi-Site Active/Active | Near-zero | Near-zero | $$$$ |

### 4. Data Resilience
- **Backup strategies:** AWS Backup, automated snapshots, point-in-time recovery
- **Replication:** Synchronous (Multi-AZ), asynchronous (cross-region)
- **Versioning:** S3 versioning + Object Lock for immutability
- **Encryption:** KMS with multi-region keys for DR
- **Data validation:** Checksum verification, backup testing automation

### 5. Compute Resilience
- **EC2:** Auto Scaling, Spot Instance diversification, capacity reservations
- **ECS/EKS:** Multi-AZ task placement, pod disruption budgets, node groups across AZs
- **Lambda:** Reserved concurrency, provisioned concurrency, multi-region deployment
- **Fargate:** Platform version pinning, capacity providers

### 6. Network Resilience
- **VPC:** Redundant NAT Gateways per AZ, VPC peering/Transit Gateway
- **DNS:** Route 53 health checks, failover policies, private hosted zones
- **Load Balancing:** Cross-zone load balancing, connection draining, health checks
- **Direct Connect:** Redundant connections, VPN backup
- **Global Accelerator:** Automatic failover, health-based routing

### 7. Application Resilience Patterns
- **Circuit Breaker:** Prevent cascading failures
- **Bulkhead:** Isolate failure domains
- **Retry with exponential backoff:** Handle transient failures
- **Queue-based load leveling:** SQS to absorb spikes
- **Throttling:** API Gateway rate limiting, WAF rate rules
- **Graceful degradation:** Feature flags, fallback responses
- **Saga pattern:** Distributed transaction management
- **CQRS:** Separate read/write paths for scalability

### 8. Observability for Resilience
- **Metrics:** CloudWatch custom metrics, composite alarms
- **Logging:** Centralized logging (CloudWatch Logs Insights, OpenSearch)
- **Tracing:** X-Ray, CloudWatch Application Signals
- **Synthetic monitoring:** CloudWatch Synthetics canaries
- **Real-user monitoring (RUM):** CloudWatch RUM
- **AIOps:** CloudWatch anomaly detection, Contributor Insights

### 9. Chaos Engineering
- **AWS Fault Injection Service (FIS):**
  - EC2 instance termination
  - AZ power interruption
  - Network latency/packet loss
  - CPU/memory stress
  - RDS failover
  - ECS task stop
- **Steady-state hypothesis → inject fault → observe → improve**
- **GameDays:** Regular failure simulation exercises

### 10. Compliance & Governance
- **AWS Resilience Hub:** Assess, track, and improve resilience posture
- **Well-Architected Reliability Pillar:** Review against best practices
- **AWS Config rules:** Monitor compliance drift
- **Service quotas:** Proactive monitoring and increase requests
- **Shared responsibility model:** Understand AWS vs customer resilience duties

## PRD Analysis Framework

When analyzing a PRD for infrastructure resilience:

1. **Identify workload tiers:** Classify components by criticality (Tier 0/1/2/3)
2. **Define RTO/RPO targets:** Per component and end-to-end
3. **Map dependencies:** Internal services, external APIs, data stores
4. **Identify single points of failure (SPOFs):** Any component without redundancy
5. **Assess blast radius:** What fails when each component fails?
6. **Recommend resilience controls:** Per component, mapped to AWS services
7. **Estimate cost impact:** Resilience improvements vs. risk reduction
8. **Define testing strategy:** How to validate resilience (FIS experiments, GameDays)
9. **Create runbooks:** Automated and manual recovery procedures
10. **Establish SLIs/SLOs:** Measurable resilience targets

## Output Format

When providing resilience recommendations:

```markdown
## Resilience Assessment: [Component/System Name]

### Current State
- Architecture overview
- Identified risks and SPOFs

### Recommendations
| # | Finding | Risk Level | Recommendation | AWS Service | Effort |
|---|---------|-----------|----------------|-------------|--------|

### Architecture Changes
- Before/After diagram description
- Migration path

### Cost Estimate
- Monthly cost delta for resilience improvements

### Testing Plan
- FIS experiments to validate
- Success criteria
```

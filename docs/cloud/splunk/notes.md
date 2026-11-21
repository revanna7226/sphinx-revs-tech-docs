# Splunk Notes for Java, Spring Boot and .NET Developers

Interview preparation and day-to-day developer usage guide for engineers with around 10 years of experience.

## 1. How to Use These Notes

At 10 years of experience, interviewers expect more than "I search logs in Splunk." They look for:

- Understanding of the architecture (how data gets in, where it is stored, how searches run)
- Fluency in SPL (Search Processing Language) for real troubleshooting
- Opinions on logging design: structure, correlation IDs, cost, PII
- Experience with alerts, dashboards, and observability (logs, metrics, traces)
- Judgment on performance, retention, and licensing cost

Sections 2 to 5 are the foundation, 6 to 9 are the daily-use skills, and 10 to 13 are interview material and practice.

## 2. Splunk Fundamentals

### 2.1 What Splunk Does

Splunk ingests machine data (logs, metrics, events, traces), indexes it, and lets you search, visualise, alert and correlate it using SPL. Main offerings:

- **Splunk Enterprise**: self-managed, on-prem or your own cloud.
- **Splunk Cloud Platform**: Splunk-managed version of Enterprise.
- **Splunk Observability Cloud**: APM, Infrastructure Monitoring, RUM, Synthetics, Log Observer. OpenTelemetry-based.
- **Splunk Enterprise Security (ES)** and **ITSI**: SIEM and service-health products on top of the platform.

### 2.2 Core Architecture

| Component | Role |
| --- | --- |
| **Universal Forwarder (UF)** | Lightweight agent that reads files and sends raw data to indexers. No parsing (mostly). |
| **Heavy Forwarder (HF)** | Full Splunk instance that can parse, filter, route and mask data before forwarding. |
| **Indexer** | Parses and indexes data, stores it in buckets, serves search requests. |
| **Search Head** | UI and search coordinator. Distributes searches to indexers, merges results. |
| **Deployment Server** | Pushes configuration to forwarders. |
| **Cluster Manager** | Coordinates indexer clustering (replication factor, search factor). |
| **HTTP Event Collector (HEC)** | HTTP/HTTPS endpoint (default port 8088) for sending events with a token. Common for apps and containers. |

Common default ports: 8000 (web UI), 8089 (management/REST API), 9997 (forwarder to indexer), 8088 (HEC).

### 2.3 Data Pipeline

1. **Input**: file monitor, HEC, syslog, scripted input, etc.
2. **Parsing**: line breaking, timestamp extraction, host/source/sourcetype assignment, index-time transforms (masking, routing).
3. **Indexing**: events written to buckets, with time-series index (tsidx) files.
4. **Search**: search-time field extraction, lookups, calculated fields, tags and event types applied.

Key point: most field extraction happens at **search time** (schema on read). Index-time extraction is used sparingly because it increases index size and cannot be changed retroactively.

### 2.4 Important Terms

- **Index**: logical repository (for example `app_prod`, `app_nonprod`). Controls retention, access and storage.
- **Source**: where data came from (file path, HEC token name).
- **Sourcetype**: format of the data (controls parsing rules). Examples: `_json`, `access_combined`, custom ones.
- **Host**: the machine or service that generated the event.
- **Bucket lifecycle**: hot (being written), warm (rolled, searchable), cold (older, cheaper storage), frozen (deleted or archived), thawed (restored).
- **Knowledge objects**: saved searches, field extractions, lookups, tags, event types, macros, data models.
- **CIM (Common Information Model)**: normalised field naming used by Splunk apps and ES.
- **License**: classically based on daily ingest volume (GB/day); other models exist. This is why log volume discipline matters.

### 2.5 Config Files You Should Recognise

- `inputs.conf`: what to monitor.
- `outputs.conf`: where forwarders send data.
- `props.conf`: parsing rules per sourcetype/source/host (line breaking, TIME\_FORMAT, SEDCMD masking, field extractions).
- `transforms.conf`: regex-based routing, extraction, lookups.
- `indexes.conf`: index definitions and retention.
- `savedsearches.conf`: saved searches and alerts.

Example props.conf for a Java app that logs multi-line stack traces:

```
[my_java_app]
SHOULD_LINEMERGE = false
LINE_BREAKER = ([\r\n]+)(?=\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})
TIME_PREFIX = ^
TIME_FORMAT = %Y-%m-%d %H:%M:%S,%3N
MAX_TIMESTAMP_LOOKAHEAD = 30
TRUNCATE = 20000
```

This is the classic fix for stack traces being split into many events. If you emit JSON logs (one line per event), most of this problem disappears.

## 3. SPL Essentials

### 3.1 Search Anatomy

```
index=app_prod sourcetype=my_service level=ERROR earliest=-4h
| stats count by service, exception
| sort - count
| head 20
```

The part before the first pipe is the base search (retrieves events from the index). Everything after is a pipeline of commands.

### 3.2 Search Performance Rules (Interview Favourite)

1. Always specify **index**, **sourcetype** and **time range**. Searching `index=*` over "All time" is the classic anti-pattern.
2. Filter as early as possible, in the base search, not with `| where` later.
3. Prefer positive terms. Avoid leading wildcards such as `*timeout`.
4. Use `fields` to drop unneeded fields early in long pipelines.
5. Prefer `stats` over `transaction`, `join` and `append` where possible.
6. Use `tstats` for fast counts on indexed fields or accelerated data models.
7. Use summary indexing, report acceleration or data model acceleration for repeated heavy dashboards.
8. Use Fast or Smart mode, not Verbose, for routine searches.

### 3.3 Commands You Must Know

| Command | Purpose | Example |
| --- | --- | --- |
| `search` / `where` | Filter. `where` uses eval expressions. | `\| where duration_ms > 2000` |
| `eval` | Create or modify fields. | `\| eval status_class=floor(status/100)*100` |
| `stats` | Aggregate (count, sum, avg, dc, perc95, values, latest). | `\| stats avg(duration_ms) perc95(duration_ms) by endpoint` |
| `eventstats` | Adds aggregate to each event without collapsing. | `\| eventstats avg(duration_ms) as avg_all` |
| `streamstats` | Running calculations in event order. | `\| streamstats count as seq by session_id` |
| `timechart` | Time-series aggregation. | `\| timechart span=5m count by status` |
| `chart` | Aggregate by two dimensions. | `\| chart count over service by level` |
| `top` / `rare` | Most/least common values. | `\| top limit=10 exception` |
| `rex` | Regex field extraction at search time. | `\| rex field=_raw "orderId=(?<orderId>\\w+)"` |
| `spath` | Extract JSON/XML paths. | `\| spath input=payload path=customer.id` |
| `table` / `fields` | Choose output columns. | `\| table _time service message` |
| `dedup` | Remove duplicates by field. | `\| dedup requestId` |
| `lookup` / `inputlookup` | Enrich with CSV or KV store. | `\| lookup service_owners service OUTPUT team` |
| `join` | Join two result sets (limited, slow). | Avoid for large data. |
| `transaction` | Group events into a transaction. | Expensive. Prefer `stats` by ID. |
| `bin` | Bucket values or time. | `\| bin _time span=1h` |
| `fillnull` | Replace nulls. | `\| fillnull value=0` |
| `append` / `appendcols` / `multisearch` | Combine searches. | Use sparingly. |
| `map` | Run a search per result row. | Slow, avoid. |
| `tstats` | Fast stats from tsidx. | `\| tstats count where index=app_prod by host` |

### 3.4 Handy Eval Functions

`if`, `case`, `coalesce`, `isnull`, `isnotnull`, `match`, `like`, `replace`, `substr`, `len`, `lower`, `upper`, `split`, `mvindex`, `mvcount`, `mvfilter`, `strftime`, `strptime`, `now`, `relative_time`, `round`, `floor`, `tonumber`, `tostring`, `json_extract`.

### 3.5 Time Modifiers

- `earliest=-15m latest=now`
- `earliest=-1d@d latest=@d` (yesterday, snapped to midnight)
- `@` snaps to a unit, for example `-1h@h`.
- Compare periods using `timewrap` or two searches combined with `appendcols`.

### 3.6 Subsearch Gotchas

Subsearches in square brackets run first and feed results to the outer search. Default limits are around 10,000 results and 60 seconds. If a subsearch silently truncates, the outer search returns wrong results. Mentioning this in an interview shows production experience.

```
index=app_prod [ search index=app_prod level=ERROR earliest=-15m | stats count by traceId | fields traceId ]
| stats values(service) as services by traceId
```

## 4. Logging From Java and Spring Boot

### 4.1 Principles

- **Log structured JSON**, one event per line. It avoids multi-line stack trace issues and makes fields searchable.
- Include consistent fields: timestamp, level, service name, environment, version, host/pod, thread, logger, message, traceId, spanId, correlationId/requestId, userId (hashed if needed), and business keys such as orderId.
- Put the stack trace in a single `exception` / `stack_trace` field.
- **Never log secrets or PII** (passwords, tokens, card numbers, national IDs, full emails). Mask at the source. Splunk masking via `SEDCMD` is a safety net, not the plan.
- Use correct levels. ERROR means a human may need to act. Do not log expected business validation failures as ERROR.
- Log at boundaries (incoming request, outgoing call, key state changes), not inside tight loops.
- Control volume. Excess DEBUG in production is a cost and performance problem.
- Use **MDC** (Mapped Diagnostic Context) to attach request-scoped fields automatically.

### 4.2 Three Ways to Get Logs Into Splunk

1. **File + Universal Forwarder**: app writes JSON to a file (or stdout captured to a file) and the UF tails it. Reliable and decoupled. Common on VMs.
2. **Container stdout + collector**: in Kubernetes, write to stdout and let the **Splunk OpenTelemetry Collector** ship logs to Splunk. Preferred for containers.
3. **Direct HEC from the app** using a Logback/Log4j2 HEC appender (`splunk-library-javalogging`). Simple, but couples the app to Splunk availability. Use async with buffering and retry, and understand what happens when HEC is down.

General recommendation: decouple the application from the log backend by writing to stdout or file and letting an agent ship.

### 4.3 Spring Boot Structured Logging

Spring Boot 3.4 and later has built-in structured logging:

```yaml
logging:
  structured:
    format:
      console: logstash   # or ecs, gelf
  level:
    root: INFO
    com.acme.orders: INFO
```

For older versions, use `logstash-logback-encoder`:

```xml
<appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
  <encoder class="net.logstash.logback.encoder.LogstashEncoder">
    <customFields>{"service":"order-service","env":"${ENV:-dev}"}</customFields>
  </encoder>
</appender>
<root level="INFO"><appender-ref ref="JSON"/></root>
```

### 4.4 Direct HEC Appender Example (Logback)

```xml
<appender name="SPLUNK" class="com.splunk.logging.HttpEventCollectorLogbackAppender">
  <url>https://splunk-hec.example.com:8088</url>
  <token>${SPLUNK_HEC_TOKEN}</token>
  <index>app_prod</index>
  <source>order-service</source>
  <sourcetype>_json</sourcetype>
  <batch_size_count>100</batch_size_count>
  <batch_interval>2000</batch_interval>
  <disableCertificateValidation>false</disableCertificateValidation>
  <layout class="ch.qos.logback.classic.PatternLayout">
    <pattern>%msg</pattern>
  </layout>
</appender>
```

Keep the token in environment variables or a secret store, never in source control. Check the library's current documentation for exact property names for your version.

### 4.5 Correlation: MDC, Trace IDs and Filters

With Micrometer Tracing (Spring Boot 3) the `traceId` and `spanId` are placed in MDC automatically. For custom IDs:

```java
@Component
public class CorrelationFilter extends OncePerRequestFilter {
  @Override
  protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
      throws ServletException, IOException {
    String id = Optional.ofNullable(req.getHeader("X-Correlation-Id"))
                        .orElse(UUID.randomUUID().toString());
    MDC.put("correlationId", id);
    res.setHeader("X-Correlation-Id", id);
    try {
      chain.doFilter(req, res);
    } finally {
      MDC.clear();
    }
  }
}
```

Propagate the header on outgoing calls (RestClient, WebClient, Feign) and into Kafka/JMS message headers. MDC is thread-local, so it is lost across `@Async`, executors and reactive chains unless you propagate it (for example with a `TaskDecorator` or Reactor context propagation).

### 4.6 Metrics and Traces Beyond Logs

- **Micrometer** with Actuator exposes JVM, HTTP and custom metrics. Export via OpenTelemetry or to Splunk Observability Cloud.
- **Splunk Distribution of OpenTelemetry Java agent**: attach with `-javaagent:splunk-otel-javaagent.jar` and set `OTEL_SERVICE_NAME` plus the exporter endpoint or Splunk access token and realm. It auto-instruments Spring MVC, JDBC, Kafka, HTTP clients and more with no code changes.
- Enable log-trace correlation so a log line in Splunk links to its trace in APM.
- Use **AlwaysOn Profiling** to find CPU and memory hotspots in production.

## 5. Logging From .NET (Microsoft Stack)

### 5.1 Options

- **Serilog** with `Serilog.Sinks.Splunk` (HEC). The most common choice.
- **NLog** or **log4net** with HEC targets, or write to file for a Universal Forwarder.
- **Microsoft.Extensions.Logging (ILogger)** as the abstraction, with Serilog as the provider.
- **OpenTelemetry .NET** SDK exporting OTLP to the Splunk OTel Collector, or the Splunk Distribution of OpenTelemetry .NET for APM.
- On Windows servers, the Universal Forwarder can also ingest **Windows Event Logs**, **IIS logs**, **performance counters** and **WMI**.

### 5.2 Serilog Example

```csharp
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("service", "payments-api")
    .WriteTo.EventCollector(
        splunkHost: "https://splunk-hec.example.com:8088",
        eventCollectorToken: Environment.GetEnvironmentVariable("SPLUNK_HEC_TOKEN"),
        index: "app_prod")
    .CreateLogger();
```

Use structured message templates (`Log.Information("Order {OrderId} paid", orderId)`), not string interpolation, so properties become searchable fields. `LogContext.PushProperty` is the .NET equivalent of MDC. ASP.NET Core adds trace and span IDs to log scopes when using `Activity`.

### 5.3 Mapping Between Java and .NET Concepts

| Concept | Java / Spring Boot | .NET |
| --- | --- | --- |
| Logging facade | SLF4J | `ILogger` |
| Implementation | Logback, Log4j2 | Serilog, NLog |
| Request-scoped context | MDC | `LogContext` / `ILogger.BeginScope` |
| Metrics | Micrometer | `System.Diagnostics.Metrics`, OpenTelemetry |
| Tracing | Micrometer Tracing, OTel Java agent | `Activity`, OTel .NET |
| Health/metrics endpoints | Actuator | Health checks middleware |
| HEC integration | `splunk-library-javalogging` | `Serilog.Sinks.Splunk` |

## 6. Day-to-Day Developer Use Cases With SPL

Adjust field names to your own log schema.

### 6.1 Find Recent Errors by Service

```
index=app_prod env=prod level=ERROR earliest=-1h
| stats count by service, exception
| sort - count
```

### 6.2 Trace a Single Request End to End

```
index=app_prod (correlationId="abc-123" OR traceId="abc-123")
| sort 0 _time
| table _time service level message
```

Use `sort 0` to avoid the default 10,000 row limit.

### 6.3 Latency Percentiles per Endpoint

```
index=app_prod sourcetype=access_json earliest=-24h
| stats count perc50(duration_ms) as p50 perc95(duration_ms) as p95 perc99(duration_ms) as p99 by uri_template
| sort - p95
```

Use `uri_template` (for example `/orders/{id}`) rather than raw URIs to avoid high-cardinality output.

### 6.4 Error Rate Over Time

```
index=app_prod service=order-service earliest=-6h
| eval is_error=if(status>=500,1,0)
| timechart span=5m sum(is_error) as errors count as total
| eval error_rate=round(errors/total*100,2)
```

### 6.5 Compare Before and After a Deployment

If you log the app `version` field:

```
index=app_prod service=order-service level=ERROR earliest=-2h
| stats count by version, exception
```

### 6.6 New Exceptions That Did Not Exist Yesterday

```
index=app_prod level=ERROR earliest=-1d@d latest=now
| eval period=if(_time>=relative_time(now(),"@d"),"today","yesterday")
| stats count(eval(period="today")) as today count(eval(period="yesterday")) as yesterday by exception
| where yesterday=0 AND today>0
```

### 6.7 Slow Downstream Dependency

```
index=app_prod event=outbound_call earliest=-1h
| stats avg(duration_ms) perc95(duration_ms) count by target_service
| sort - perc95(duration_ms)
```

### 6.8 Parse Unstructured Logs

```
index=legacy sourcetype=app_log "Payment failed"
| rex "orderId=(?<orderId>\\d+)\\s+reason=(?<reason>[^,]+)"
| stats count by reason
```

### 6.9 Business Questions

```
index=app_prod event="order_created" earliest=-7d@d
| timechart span=1d count by channel
```

Developers often get asked "how many orders failed payment last Tuesday?" Good structured logs let you answer in seconds.

## 7. Alerts, Dashboards and Reports

### 7.1 Alerts

- **Scheduled alert**: runs on a cron schedule, triggers when conditions are met (for example results > 0).
- **Real-time alert**: runs continuously. Expensive, use rarely. Prefer scheduled alerts every 1 to 5 minutes.
- **Trigger conditions**: number of results, hosts, sources, or a custom condition. Choose "once" or "for each result".
- **Throttling** suppresses repeat alerts for a window so you do not flood the on-call.
- **Actions**: email, webhook (PagerDuty, Slack, Teams, ServiceNow), script, Triggered Alerts list.

Example alert search (error rate above threshold):

```
index=app_prod service=payments earliest=-5m
| stats count as total count(eval(level="ERROR")) as errors
| eval rate=round(errors/total*100,2)
| where total>50 AND rate>5
```

The `total>50` guard avoids noise from low-traffic periods.

### 7.2 Good Alerting Practice

- Alert on symptoms users feel (error rate, latency, saturation), not every exception.
- Every alert needs an owner, a runbook link and a clear severity.
- Review noisy alerts regularly. Alert fatigue is a reliability risk.
- Use SLO or burn-rate style alerts where possible.

### 7.3 Dashboards

- Use **Dashboard Studio** (modern) or Classic Simple XML dashboards.
- Use **tokens** for input filters (time range, environment, service) and drilldowns.
- Use **base searches** and **post-process searches** so many panels reuse one expensive query.
- Schedule or accelerate heavy panels.
- Put the golden signals first: traffic, errors, latency, saturation.

### 7.4 Other Knowledge Objects

- **Macros** to reuse SPL snippets.
- **Lookups** to map service to owner, error code to description, or IP to location.
- **Event types and tags** to group events logically.
- **Saved searches and reports** shared via apps with role-based permissions.

## 8. Splunk Observability Cloud (Brief)

- **APM**: service map, trace analyzer, Tag Spotlight, error and latency breakdowns. Receives traces via OpenTelemetry.
- **Infrastructure Monitoring**: metrics from hosts, containers and Kubernetes, with real-time streaming and detectors.
- **RUM**: browser and mobile user experience monitoring.
- **Synthetics**: scripted uptime and journey checks.
- **Log Observer / Log Observer Connect**: view Splunk logs in context of traces and metrics.
- **Splunk OpenTelemetry Collector**: the standard agent for logs, metrics and traces, deployed on hosts or via Helm in Kubernetes.

Interview angle: explain the three pillars (logs, metrics, traces), when each is the right tool, and how correlation by trace ID ties them together.

## 9. Security, Governance and Cost

- **RBAC**: roles control index access and capabilities. Separate prod and non-prod indexes.
- **Data masking**: `SEDCMD` in props.conf or ingest-time rules at a heavy forwarder or OTel collector.
- **TLS** between forwarders and indexers, and for HEC. Rotate HEC tokens.
- **Retention**: set per index (`frozenTimePeriodInSecs`, size limits). Align with compliance requirements.
- **Cost control**: reduce noisy logs, drop health-check lines, sample debug logs, route low-value data to cheaper indexes, and monitor licence usage in the Monitoring Console.
- **Compliance**: avoid PII in logs. If it must be logged, mask or tokenise it.

## 10. Interview Questions and Model Answers

### 10.1 Architecture and Concepts

**Q1. Explain Splunk architecture.** Forwarders collect and send data, indexers parse and store it in buckets, and search heads coordinate searches across indexers. Supporting components are the deployment server, cluster manager and license manager. Applications can also send via HEC or syslog.

**Q2. Universal Forwarder vs Heavy Forwarder?** UF is lightweight, with minimal CPU and memory, and forwards mostly unparsed data. HF is a full instance that can parse, filter, mask, route and run scripted inputs or add-ons, at higher resource cost. Use UF by default and HF when you need parsing or routing before data reaches indexers.

**Q3. What is HEC and when would you use it?** HTTP Event Collector is a token-authenticated HTTP(S) endpoint for sending events directly. Good for cloud-native apps, serverless and containers. Trade-offs are coupling to Splunk availability and the need for buffering and retries on the client side.

**Q4. Index time vs search time?** Index time covers parsing, timestamping, host/source/sourcetype and index-time transforms. Search time covers field extraction, lookups, tags and calculated fields. Splunk favours search time for flexibility. Index-time fields are fast but permanent and increase storage.

**Q5. Explain bucket lifecycle.** Hot, warm, cold, frozen, thawed. Hot is actively written, warm is rolled and searchable, cold sits on cheaper storage, frozen is deleted or archived by retention policy, and thawed is restored from archive.

**Q6. What is a sourcetype and why does it matter?** It defines how Splunk parses data (line breaking, timestamps, extractions). Wrong sourcetypes cause broken events and bad timestamps.

**Q7. How does indexer clustering work?** Indexers replicate buckets based on the replication factor, while the search factor determines how many copies are searchable. The cluster manager coordinates peers and handles failures.

**Q8. What are knowledge objects?** Saved searches, field extractions, lookups, tags, event types, macros, data models and workflow actions. They are shared through apps with permissions.

### 10.2 SPL

**Q9. `stats` vs `eventstats` vs `streamstats`?** `stats` collapses events into aggregate rows. `eventstats` adds aggregates to every original event. `streamstats` computes running values in event order.

**Q10. `stats` vs `transaction`?** `transaction` groups events by fields and time constraints and keeps raw events, but is memory-heavy and slow. `stats` by an ID with `min(_time)`, `max(_time)` and `values()` is usually faster and scales better.

**Q11. Why avoid `join`?** It runs a subsearch with result and time limits, is not distributed efficiently, and often truncates silently. Prefer `stats` after combining datasets with a shared key, or use `lookup`.

**Q12. How do you speed up a slow search?** Narrow index, sourcetype and time range. Filter early. Drop unneeded fields. Replace transaction/join with stats. Use `tstats`, summary indexing or accelerated data models. Avoid leading wildcards. Check the job inspector to see where time is spent.

**Q13. What does `tstats` do?** Runs statistical queries directly on index metadata and accelerated data, which makes it much faster than raw event searches. It works with indexed fields or accelerated data models.

**Q14. How do you extract a field from raw text?** Use `rex` for ad hoc searches, or define a field extraction (props/transforms or the Field Extractor UI) for permanent use. For JSON use `spath` or automatic extraction with `KV_MODE=json`.

**Q15. How do you calculate p95 latency?** `| stats perc95(duration_ms) as p95 by endpoint`.

**Q16. What are subsearch limits?** Defaults are around 10,000 results and 60 seconds runtime. Results beyond that are silently dropped, which can cause wrong answers.

**Q17. What is the difference between `search` and `where`?** `search` uses search syntax (case-insensitive field matches, wildcards). `where` evaluates eval expressions (case-sensitive string comparisons, functions, numeric operations).

**Q18. How do you find hosts that stopped logging?** Use `stats latest(_time)` by host and compare with now, or compare against a lookup of expected hosts. `| metadata type=hosts` is a quick option too.

### 10.3 Java, Spring Boot and .NET Usage

**Q19. How do you design logging for microservices so Splunk is useful?** Structured JSON logs, consistent schema across services, correlation and trace IDs propagated across HTTP and messaging, service/env/version fields, sensible levels, no PII, and a shipping approach that decouples the app from Splunk (stdout/file with an agent).

**Q20. How do you trace a request across services in Splunk?** Propagate `traceId` (W3C `traceparent`) or a correlation ID via headers and message headers, include it in MDC or log scope, then search by that ID and sort by time. With OpenTelemetry, use the APM trace view and link to logs.

**Q21. MDC is lost in async code. How do you handle it?** Copy the MDC context map to the worker thread using a `TaskDecorator` or wrapped executor. In reactive code use Reactor context propagation (the Micrometer context-propagation library) so trace and correlation IDs survive thread hops.

**Q22. How do you handle multi-line stack traces?** Preferably log JSON so the stack trace is one field. Otherwise set `LINE_BREAKER` and `SHOULD_LINEMERGE=false` in props.conf using a regex matching the timestamp at line start.

**Q23. What happens if Splunk or HEC is down?** With a direct appender, you rely on client buffering and retry, and risk dropped logs or blocked threads if the appender is synchronous. With file/stdout plus a forwarder, the agent buffers (and persistent queues can be enabled), so the application is isolated. This is why decoupling is the usual choice.

**Q24. How would you configure Serilog for Splunk?** Use `Serilog.Sinks.Splunk` with the HEC URL and token from configuration or secrets, enrich with service, environment and trace properties, use structured templates, and set minimum levels with overrides for noisy `Microsoft.*` namespaces.

**Q25. How do you stop sensitive data from reaching Splunk?** Prevent it in code (do not log it, use masking converters or Serilog destructuring policies), reinforce with ingest-time masking (`SEDCMD`, HF rules, OTel processors), restrict index access by role, and review logging in code reviews and tests.

**Q26. How do you use Splunk during a performance investigation?** Start with error rate and latency percentiles by endpoint, find the time the problem began, correlate with deployments (version field), check dependency latency, look at JVM/GC or CLR metrics, then drill into a slow trace and its logs. Confirm the fix by comparing before and after.

**Q27. Log-based metrics vs real metrics?** Logs are rich and good for debugging but expensive to aggregate at scale. Metrics (Micrometer or OpenTelemetry) are cheap, pre-aggregated and better for alerting and dashboards. Use logs for investigation, metrics for monitoring, and traces for request flow.

### 10.4 Operations and Design

**Q28. How do you reduce Splunk licence cost?** Drop health-check and noisy debug logs at source, lower log levels in production, filter at HF or collector, avoid duplicate logging (app and platform), send metrics to metrics indexes, and apply different retention per index.

**Q29. How do you design indexes?** Separate by retention, access and data volume: for example by environment and data type (`app_prod`, `app_nonprod`, `security`, `metrics_prod`). Do not create one index per service, which creates management overhead.

**Q30. How do you set up a good alert?** Define the user-facing symptom, choose a scheduled search with a sensible window, add minimum-volume guards, throttle, route to the right on-call channel, and attach a runbook. Review false positives after each incident.

**Q31. What is the Monitoring Console?** A built-in app that shows health and performance of the Splunk deployment: indexing rate, search load, licence usage, forwarder connectivity and queue status.

**Q32. Splunk vs ELK vs Datadog?** Splunk: very strong search language, enterprise security use cases, mature governance, but cost scales with ingest. ELK/OpenSearch: open source, flexible, more operational effort. Datadog: SaaS with a strong integrated APM and infrastructure experience, priced per host and per volume. The right choice depends on cost model, existing tooling and team skills.

### 10.5 Scenario Questions

**S1. Production API latency doubled in the last hour. Walk me through it.**

1. Confirm scope: `timechart perc95(duration_ms) by service` to see which services are affected and when it started.
2. Compare with the deployment time using a `version` field.
3. Break down by endpoint and by downstream dependency (`target_service`).
4. Check error rate, timeouts, retries, and thread pool or connection pool saturation messages.
5. Pull a slow trace (APM) or search by `traceId` for a slow request and read its logs.
6. Check infrastructure metrics (CPU, GC pauses, DB connections).
7. Mitigate (rollback, scale, circuit breaker), then write up the root cause.

**S2. Logs for one service stopped appearing in Splunk.** Check whether the app is still logging (pod or VM logs), whether the forwarder or collector is running and can read the file, the `inputs.conf` path, forwarder connectivity (`splunkd.log` and the `_internal` index), HEC token or index permission errors, blocked queues, and licence violations. Use `index=_internal` to see forwarder and HEC errors.

**S3. Timestamps are wrong or events are merged.** Check `TIME_PREFIX`, `TIME_FORMAT`, `MAX_TIMESTAMP_LOOKAHEAD`, time zone settings and `LINE_BREAKER`. Fix in props.conf on the first full Splunk instance in the data path (heavy forwarder or indexer), then test with fresh data.

**S4. Design logging for a new set of 20 Spring Boot microservices.** A shared logging library or Spring Boot starter that configures JSON output, MDC fields and masking. A common field schema. Trace propagation with OpenTelemetry. One or two indexes per environment. OTel Collector or UF shipping. Standard dashboards and alerts kept as code (saved searches in version control). Guidelines on levels and volume, plus a PII review.

**S5. Find customers affected by a failed batch job.** Search for the job's failure events by `jobId`, extract `customerId` with `rex` or `spath`, `dedup` it, use `lookup` to enrich with region or contact data if allowed, and export the result or schedule a report. Mention PII handling.

## 11. Quick Cheat Sheet

**Search skeleton**

```
index=<idx> sourcetype=<st> <keywords> earliest=-1h
| fields <needed fields>
| eval ...
| stats <agg> by <field>
| sort - <field>
| head 20
```

**Remember**

- Time range, index and sourcetype first.
- `stats` beats `transaction` and `join`.
- `sort 0` removes the 10,000 row default limit.
- JSON logs: `spath` or automatic key-value extraction.
- Percentiles: `perc95(field)`.
- Trends: `timechart span=5m`.
- Debug the platform with `index=_internal`.
- Do not log PII. Mask at source.
- Decouple apps from Splunk, with buffering and retry.
- Include `traceId`, `service`, `env` and `version` in every log line.

## 12. Seven-Day Preparation Plan

| Day | Focus |
| --- | --- |
| 1 | Architecture, data pipeline, terminology. Read sections 2 and 9 and explain them aloud. |
| 2 | SPL basics: stats, eval, rex, timechart, top. Practise on a Splunk trial or the free tutorial data. |
| 3 | Advanced SPL: eventstats, streamstats, lookups, subsearches, tstats, performance tuning. |
| 4 | Java/Spring Boot logging: JSON logs, MDC, HEC appender or collector. Build a small demo service and view its logs in Splunk. |
| 5 | .NET equivalents (Serilog, ILogger) and OpenTelemetry tracing. |
| 6 | Alerts, dashboards, tokens, Observability Cloud concepts. Build one dashboard with four panels. |
| 7 | Mock interview: answer sections 10.1 to 10.5 out loud, then rehearse two STAR stories where Splunk helped you solve a production incident. |

### STAR Template for Behavioural Questions

- **Situation**: the production issue and its business impact.
- **Task**: what you owned.
- **Action**: the specific queries, dashboards or logging changes you made, and what they revealed.
- **Result**: time to detect or resolve, errors reduced, alert noise reduced, cost saved.

Have at least one story each for incident troubleshooting, improving logging or observability, and reducing noise or cost.

## 13. Suggested Hands-On Practice

1. Run Splunk locally (the `splunk/splunk` Docker image works) and enable HEC.
2. Create a Spring Boot REST service that logs JSON with `traceId` and `correlationId`, and send the logs to HEC.
3. Create a small ASP.NET Core API with Serilog sending to the same HEC.
4. Generate load and write queries for error rate, p95 latency and top exceptions.
5. Build a dashboard with a service dropdown token, and an alert with throttling.
6. Attach the Splunk OTel Java agent and view traces in an Observability Cloud trial.

Good luck with the preparation.

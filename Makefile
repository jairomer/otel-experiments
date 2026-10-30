OTLP_HTTP ?= localhost:4318
OTEL_CLI ?= otel-cli
OTEL_SERVICE ?= verify-test

# otel-cli reads these when no --endpoint flag is given; without them it runs
# in non-recording mode and silently sends nothing.
export OTEL_EXPORTER_OTLP_ENDPOINT := http://$(OTLP_HTTP)
export OTEL_EXPORTER_OTLP_PROTOCOL := http/protobuf

.PHONY: run test test-status test-traces test-metrics test-logs

run:
	podman run \
		--network host \
		-v "./config.yml":/etc/otel-config.yaml \
		docker.io/otel/opentelemetry-collector:latest \
		--config=/etc/otel-config.yaml

test: test-traces test-metrics test-logs

# Connectivity check: sends a single canary span and exits non-zero on failure.
test-status:
	@$(OTEL_CLI) status --fail --verbose | grep -E '"(endpoint|error)"'

test-traces:
	$(OTEL_CLI) exec --service $(OTEL_SERVICE) --name make-test-traces --kind client \
		--attrs test.signal=traces,http.method=GET,http.status_code=200 -- \
		curl -sS -f -o /dev/null -w 'traces:   HTTP %{http_code}\n' \
			-X POST http://$(OTLP_HTTP)/v1/traces \
			-H 'Content-Type: application/json' \
			-d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"verify-test"}}]},"scopeSpans":[{"scope":{"name":"make-test"},"spans":[{"traceId":"5b8efff798038103d269b633813fc60c","spanId":"eee19b7ec3c1b174","name":"local-test","kind":1,"startTimeUnixNano":"1544712660000000000","endTimeUnixNano":"1544712661000000000","attributes":[{"key":"http.method","value":{"stringValue":"GET"}},{"key":"http.status_code","value":{"intValue":"200"}}]}]}]}]}'

# otel-cli (equinix-labs v0.4.x) emits traces only, so the OTLP metrics and logs
# payloads are still posted directly; otel-cli wraps them in a span so each test
# is traced.
test-metrics:
	$(OTEL_CLI) exec --service $(OTEL_SERVICE) --name make-test-metrics --kind client \
		--attrs test.signal=metrics,test.metric=verify -- \
		curl -sS -f -o /dev/null -w 'metrics:  HTTP %{http_code}\n' \
			-X POST http://$(OTLP_HTTP)/v1/metrics \
			-H 'Content-Type: application/json' \
			-d '{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"verify-test"}}]},"scopeMetrics":[{"scope":{"name":"make-test"},"metrics":[{"name":"verify.counter","unit":"1","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"7","timeUnixNano":"1544712660000000000","attributes":[{"key":"test.metric","value":{"stringValue":"verify"}}]}]}}]}]}]}'

test-logs:
	$(OTEL_CLI) exec --service $(OTEL_SERVICE) --name make-test-logs --kind client \
		--attrs test.signal=logs,test.log=verify -- \
		curl -sS -f -o /dev/null -w 'logs:     HTTP %{http_code}\n' \
			-X POST http://$(OTLP_HTTP)/v1/logs \
			-H 'Content-Type: application/json' \
			-d '{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"verify-test"}}]},"scopeLogs":[{"scope":{"name":"make-test"},"logRecords":[{"timeUnixNano":"1544712660000000000","observedTimeUnixNano":"1544712660000000000","severityNumber":9,"severityText":"INFO","body":{"stringValue":"hello from make test"},"attributes":[{"key":"test.log","value":{"stringValue":"verify"}}]}]}]}]}'

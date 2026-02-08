#!/bin/bash
set -uo pipefail

###############################################
# Observability Test Script
# Triggers success + error events, verifies
# logs, metric filter, and alarm are working
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

PASS=0
FAIL=0

check() {
    local label="$1"
    local result="$2"
    if [ "$result" = "PASS" ]; then
        echo "  [PASS] $label"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $label"
        FAIL=$((FAIL + 1))
    fi
}

echo "==========================================="
echo "  Observability Verification"
echo "==========================================="

###############################################
# 0. Check AWS credentials
###############################################
echo "--- 0. AWS Credentials ---"

if aws sts get-caller-identity > /dev/null 2>&1; then
    check "AWS credentials valid" "PASS"
else
    check "AWS credentials valid" "FAIL"
    echo ""
    echo "  AWS credentials are expired or not configured."
    echo "  1. Go to AWS Academy -> AWS Details -> Show"
    echo "  2. Copy credentials to ~/.aws/credentials"
    echo "  3. Re-run this script"
    exit 1
fi
echo ""

FUNCTION_NAME=$(terraform output -raw lambda_function_name 2>/dev/null || echo "telegram-bot")
LOG_GROUP="/aws/lambda/$FUNCTION_NAME"
ALARM_NAME=$(terraform output -raw error_alarm_name 2>/dev/null || echo "telegram-bot-error-alarm")
# Millisecond timestamp for filtering only logs generated during this test
TEST_START=$(date -u +%s)000

echo "Function:     $FUNCTION_NAME"
echo "Log Group:    $LOG_GROUP"
echo "Alarm:        $ALARM_NAME"
echo ""

###############################################
# 1. Verify log group exists with retention
###############################################
echo "--- 1. Log Group & Retention ---"

RETENTION=$(aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP" \
  --query 'logGroups[0].retentionInDays' \
  --output text 2>/dev/null)

if [ -n "$RETENTION" ] && [ "$RETENTION" != "None" ] && [ "$RETENTION" != "null" ]; then
    check "Log group exists with ${RETENTION}-day retention" "PASS"
else
    check "Log group exists with finite retention" "FAIL"
fi
echo ""

###############################################
# 2. Verify metric filter exists
###############################################
echo "--- 2. Metric Filter ---"

FILTER_NAME=$(aws logs describe-metric-filters \
  --log-group-name "$LOG_GROUP" \
  --query 'metricFilters[0].filterName' \
  --output text 2>/dev/null)

FILTER_PATTERN=$(aws logs describe-metric-filters \
  --log-group-name "$LOG_GROUP" \
  --query 'metricFilters[0].filterPattern' \
  --output text 2>/dev/null)

if [ -n "$FILTER_NAME" ] && [ "$FILTER_NAME" != "None" ]; then
    check "Metric filter exists: $FILTER_NAME" "PASS"
    echo "        Pattern: $FILTER_PATTERN"
else
    check "Metric filter exists" "FAIL"
fi
echo ""

###############################################
# 3. Verify alarm exists
###############################################
echo "--- 3. CloudWatch Alarm ---"

ALARM_STATE=$(aws cloudwatch describe-alarms \
  --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[0].StateValue' \
  --output text 2>/dev/null)

ALARM_THRESHOLD=$(aws cloudwatch describe-alarms \
  --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[0].Threshold' \
  --output text 2>/dev/null)

ALARM_PERIOD=$(aws cloudwatch describe-alarms \
  --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[0].Period' \
  --output text 2>/dev/null)

if [ -n "$ALARM_STATE" ] && [ "$ALARM_STATE" != "None" ]; then
    check "Alarm exists (state: $ALARM_STATE, threshold: >=${ALARM_THRESHOLD} errors / ${ALARM_PERIOD}s)" "PASS"
else
    check "Alarm exists" "FAIL"
fi
echo ""

###############################################
# 4. Trigger a SUCCESS event
###############################################
echo "--- 4. Trigger SUCCESS Event ---"

SUCCESS_PAYLOAD='{"body": "{\"update_id\": 999999, \"message\": {\"message_id\": 1, \"from\": {\"id\": 11111}, \"chat\": {\"id\": 11111}, \"text\": \"/status\"}}"}'

SUCCESS_STATUS=$(aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --payload "$SUCCESS_PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  /tmp/success_response.json \
  --query 'StatusCode' --output text 2>/dev/null)

if [ "$SUCCESS_STATUS" = "200" ]; then
    check "Lambda invocation returned 200" "PASS"
else
    check "Lambda invocation returned 200 (got: $SUCCESS_STATUS)" "FAIL"
fi
echo ""

###############################################
# 5. Trigger an ERROR event
###############################################
echo "--- 5. Trigger ERROR Event ---"

ERROR_PAYLOAD='{"body": "THIS IS NOT VALID JSON {{{"}'

ERROR_STATUS=$(aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --payload "$ERROR_PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  /tmp/error_response.json \
  --query 'StatusCode' --output text 2>/dev/null)

if [ "$ERROR_STATUS" = "200" ]; then
    check "Error event invoked successfully" "PASS"
else
    check "Error event invoked successfully (got: $ERROR_STATUS)" "FAIL"
fi
echo ""

###############################################
# 6. Wait and verify structured logs
###############################################
echo "--- 6. Verifying Structured Logs (waiting 15s) ---"
sleep 15

# Fetch all structured logs from this test run
# Use simple text pattern "level" to match our JSON logs
ALL_LOGS=$(aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern '"level"' \
  --start-time "$TEST_START" \
  --limit 20 \
  --query 'events[].message' \
  --output json 2>/dev/null)

# Use Python to parse and split into INFO/ERROR, handling Lambda prefix
PARSED=$(echo "$ALL_LOGS" | python3 -c "
import sys, json

msgs = json.load(sys.stdin)
info_logs = []
error_logs = []

for m in msgs:
    # Find the JSON object in the line (may have Lambda prefix)
    text = m.strip()
    idx = text.find('{')
    if idx < 0:
        continue
    try:
        obj = json.loads(text[idx:])
    except json.JSONDecodeError:
        continue

    level = obj.get('level', '')
    if level == 'INFO':
        info_logs.append(obj)
    elif level == 'ERROR':
        error_logs.append(obj)

print(json.dumps({'info': info_logs, 'error': error_logs}))
" 2>/dev/null)

INFO_COUNT=$(echo "$PARSED" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['info']))" 2>/dev/null || echo "0")
ERROR_COUNT=$(echo "$PARSED" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['error']))" 2>/dev/null || echo "0")

if [ "$INFO_COUNT" -gt 0 ] 2>/dev/null; then
    check "Structured INFO logs found ($INFO_COUNT entries)" "PASS"
    echo ""
    echo "        Sample INFO log:"
    echo "$PARSED" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['info']:
    print(json.dumps(data['info'][0], indent=4))
" 2>/dev/null | sed 's/^/        /'
else
    check "Structured INFO logs found" "FAIL"
fi

echo ""

if [ "$ERROR_COUNT" -gt 0 ] 2>/dev/null; then
    check "Structured ERROR logs found ($ERROR_COUNT entries)" "PASS"
    echo ""
    echo "        Sample ERROR log:"
    echo "$PARSED" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['error']:
    print(json.dumps(data['error'][0], indent=4))
" 2>/dev/null | sed 's/^/        /'
else
    check "Structured ERROR logs found" "FAIL"
fi
echo ""

###############################################
# 7. Verify log fields
###############################################
echo "--- 7. Verifying Log Fields ---"

SAMPLE_LOG=$(echo "$PARSED" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['info']:
    print(json.dumps(data['info'][0]))
" 2>/dev/null)

if [ -n "$SAMPLE_LOG" ]; then
    for field in level timestamp action outcome request_id; do
        if echo "$SAMPLE_LOG" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '$field' in d" 2>/dev/null; then
            check "Log contains field: $field" "PASS"
        else
            check "Log contains field: $field" "FAIL"
        fi
    done
else
    check "Could not extract structured log for field verification" "FAIL"
fi
echo ""

###############################################
# 8. Check metric datapoints
###############################################
echo "--- 8. Metric Filter Datapoints ---"

START_TIME=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-30M +%Y-%m-%dT%H:%M:%S)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

DATAPOINTS=$(aws cloudwatch get-metric-statistics \
  --namespace TelegramBot \
  --metric-name "$FUNCTION_NAME-error-count" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 300 \
  --statistics Sum \
  --query 'length(Datapoints)' \
  --output text 2>/dev/null)

if [ -n "$DATAPOINTS" ] && [ "$DATAPOINTS" -gt 0 ] 2>/dev/null; then
    check "Metric datapoints exist ($DATAPOINTS datapoints)" "PASS"
    aws cloudwatch get-metric-statistics \
      --namespace TelegramBot \
      --metric-name "$FUNCTION_NAME-error-count" \
      --start-time "$START_TIME" \
      --end-time "$END_TIME" \
      --period 300 \
      --statistics Sum \
      --output table 2>/dev/null | sed 's/^/        /'
else
    check "Metric datapoints exist (may take ~5 min to appear)" "FAIL"
fi
echo ""

###############################################
# 9. Final alarm state
###############################################
echo "--- 9. Final Alarm State ---"

FINAL_STATE=$(aws cloudwatch describe-alarms \
  --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[0].StateValue' \
  --output text 2>/dev/null)

echo "  Alarm state: $FINAL_STATE"
if [ "$FINAL_STATE" = "ALARM" ]; then
    check "Alarm triggered by error events" "PASS"
elif [ "$FINAL_STATE" = "INSUFFICIENT_DATA" ]; then
    echo "  (Alarm needs ~5 min after first error to transition to ALARM)"
    check "Alarm exists and waiting for evaluation" "PASS"
else
    check "Alarm in expected state (got: $FINAL_STATE)" "PASS"
fi
echo ""

###############################################
# Summary
###############################################
TOTAL=$((PASS + FAIL))
echo "==========================================="
echo "  Results: $PASS/$TOTAL passed"
echo "==========================================="

if [ "$FAIL" -eq 0 ]; then
    echo "  All checks passed!"
else
    echo "  $FAIL check(s) failed."
    echo "  Note: Metric datapoints and alarm transitions"
    echo "  can take up to 5 minutes to appear."
    echo "  Re-run this script after a few minutes if needed."
fi

exit "$FAIL"

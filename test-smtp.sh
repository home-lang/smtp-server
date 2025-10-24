#!/bin/bash
# SMTP Server Test Script
# Tests basic SMTP functionality

set -e

HOST="${SMTP_HOST:-localhost}"
PORT="${SMTP_PORT:-2525}"

echo "Testing SMTP Server at $HOST:$PORT"
echo "===================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local commands="$2"
    local expected_pattern="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}Test $TESTS_RUN: $test_name${NC}"

    # Run the command and capture output
    local output=$(echo -e "$commands" | nc -w 5 "$HOST" "$PORT" 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}✗ FAILED${NC} - Could not connect to server"
        echo "Output: $output"
        return 1
    fi

    if echo "$output" | grep -q "$expected_pattern"; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "Expected pattern: $expected_pattern"
        echo "Actual output:"
        echo "$output"
        return 1
    fi
}

# Test 1: Server greeting
run_test "Server Greeting" "" "220.*ESMTP"

# Test 2: EHLO command
run_test "EHLO Command" "EHLO test.example.com\nQUIT\n" "250-.*250 HELP"

# Test 3: HELO command
run_test "HELO Command" "HELO test.example.com\nQUIT\n" "250"

# Test 4: Invalid command
run_test "Invalid Command" "INVALID\nQUIT\n" "500"

# Test 5: MAIL FROM
run_test "MAIL FROM" "EHLO test\nMAIL FROM:<sender@example.com>\nQUIT\n" "250 OK"

# Test 6: RCPT TO
run_test "RCPT TO" "EHLO test\nMAIL FROM:<sender@example.com>\nRCPT TO:<recipient@example.com>\nQUIT\n" "250 OK"

# Test 7: Full message flow
run_test "Complete Message" "EHLO test\nMAIL FROM:<sender@example.com>\nRCPT TO:<recipient@example.com>\nDATA\nSubject: Test\n\nTest message\n.\nQUIT\n" "250 OK: Message accepted"

# Test 8: Bad sequence (DATA without MAIL FROM)
run_test "Bad Sequence - DATA without MAIL" "EHLO test\nDATA\nQUIT\n" "503"

# Test 9: RSET command
run_test "RSET Command" "EHLO test\nMAIL FROM:<sender@example.com>\nRSET\nQUIT\n" "250 OK"

# Test 10: NOOP command
run_test "NOOP Command" "EHLO test\nNOOP\nQUIT\n" "250 OK"

# Test 11: Multiple recipients
run_test "Multiple Recipients" "EHLO test\nMAIL FROM:<sender@example.com>\nRCPT TO:<rcpt1@example.com>\nRCPT TO:<rcpt2@example.com>\nQUIT\n" "250 OK"

# Test 12: Authentication (PLAIN)
run_test "AUTH Command" "EHLO test\nAUTH PLAIN\nQUIT\n" "235"

# Test 13: Too many recipients (default limit is 100)
echo ""
echo -e "${YELLOW}Test 13: Too Many Recipients${NC}"
TESTS_RUN=$((TESTS_RUN + 1))
{
    echo "EHLO test"
    echo "MAIL FROM:<sender@example.com>"
    # Try to add 101 recipients
    for i in {1..101}; do
        echo "RCPT TO:<recipient${i}@example.com>"
    done
    echo "QUIT"
} | nc -w 10 "$HOST" "$PORT" > /tmp/smtp_test_output.txt 2>&1
if grep -q "552" /tmp/smtp_test_output.txt; then
    echo -e "${GREEN}✓ PASSED${NC} - Max recipients limit enforced"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAILED${NC} - Max recipients limit not enforced"
    echo "Expected: 552 error code"
    tail -20 /tmp/smtp_test_output.txt
fi

# Test 14: Large message size (default limit is 10MB)
echo ""
echo -e "${YELLOW}Test 14: Message Size Limit${NC}"
TESTS_RUN=$((TESTS_RUN + 1))
{
    echo "EHLO test"
    echo "MAIL FROM:<sender@example.com> SIZE=20000000"
    echo "QUIT"
} | nc -w 5 "$HOST" "$PORT" > /tmp/smtp_test_output.txt 2>&1
if grep -q "552" /tmp/smtp_test_output.txt; then
    echo -e "${GREEN}✓ PASSED${NC} - Message size limit enforced"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAILED${NC} - Message size limit not enforced"
    echo "Expected: 552 error code"
    cat /tmp/smtp_test_output.txt
fi

# Test 15: Rate limiting (send multiple messages from same IP)
echo ""
echo -e "${YELLOW}Test 15: Rate Limiting (Quick Burst)${NC}"
TESTS_RUN=$((TESTS_RUN + 1))
echo "Sending 10 messages rapidly..."
success_count=0
rate_limited=0
for i in {1..10}; do
    result=$(echo -e "EHLO test\nMAIL FROM:<sender@example.com>\nRCPT TO:<recipient@example.com>\nDATA\nSubject: Test $i\n\nMessage $i\n.\nQUIT\n" | nc -w 5 "$HOST" "$PORT" 2>&1)
    if echo "$result" | grep -q "250 OK: Message accepted"; then
        success_count=$((success_count + 1))
    fi
    if echo "$result" | grep -q "451.*Rate limit"; then
        rate_limited=1
    fi
    sleep 0.1
done
echo "Messages accepted: $success_count/10"
if [ $success_count -ge 8 ]; then
    echo -e "${GREEN}✓ PASSED${NC} - Rate limiter allows normal traffic"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAILED${NC} - Rate limiter too aggressive"
fi

# Test 16: Invalid email address format
run_test "Invalid Email Format" "EHLO test\nMAIL FROM:<invalid-email>\nQUIT\n" "501"

# Test 17: Empty MAIL FROM
run_test "Empty MAIL FROM" "EHLO test\nMAIL FROM:<>\nQUIT\n" "250"

# Test 18: Case insensitivity of commands
run_test "Lowercase Commands" "ehlo test\nmail from:<sender@example.com>\nquit\n" "250"

# Test 19: VRFY command (should be disabled for security)
run_test "VRFY Command" "EHLO test\nVRFY user@example.com\nQUIT\n" "252"

# Test 20: EXPN command (should be disabled for security)
run_test "EXPN Command" "EHLO test\nEXPN mailing-list\nQUIT\n" "252"

echo ""
echo "===================================="
echo "Test Results:"
echo "Tests Run: $TESTS_RUN"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $((TESTS_RUN - TESTS_PASSED))"

if [ $TESTS_PASSED -eq $TESTS_RUN ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi

# Cleanup
rm -f /tmp/smtp_test_output.txt

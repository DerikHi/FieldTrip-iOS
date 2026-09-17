#!/usr/bin/env bash
#
# backend-auth-tests.sh — black-box auth/authorization checks for the
# FieldTrip Vercel backend. Proves what the server actually enforces,
# independent of the iOS client.
#
# USAGE:
#   1. Create two VERIFIED accounts in the app: User A and User B.
#   2. (Optional, for the IDOR test) As User A, create an insight entry and
#      grab its id — pass it as A_ENTRY_ID below.
#   3. Fill in the env vars and run:  bash backend-auth-tests.sh
#
# Tokens are minted via Firebase's signInWithPassword REST endpoint using the
# public iOS API key (same key shipped in the app — not a secret).
#
# Endpoints below were taken verbatim from the iOS client, so they match what
# the app calls. Adjust if the backend differs.

set -uo pipefail

# ----------------------------------------------------------------------------
# CONFIG — fill these in (or export them before running)
# ----------------------------------------------------------------------------
BASE="${BASE:-https://backend-nine-kappa-58.vercel.app}"
API_KEY="${API_KEY:-AIzaSyCk3pm2hHl7UsEQROyYIKFp3Mik5AHeVYI}"  # public iOS key

EMAIL_A="${EMAIL_A:-}"        # a verified test account
PASSWORD_A="${PASSWORD_A:-}"
EMAIL_B="${EMAIL_B:-}"        # a second verified test account
PASSWORD_B="${PASSWORD_B:-}"

# Optional extras:
A_ENTRY_ID="${A_ENTRY_ID:-}"                 # an insight id owned by User A (enables IDOR test)
EMAIL_UNVERIFIED="${EMAIL_UNVERIFIED:-}"     # an account that has NOT verified its email
PASSWORD_UNVERIFIED="${PASSWORD_UNVERIFIED:-}"

# ----------------------------------------------------------------------------
# Plumbing
# ----------------------------------------------------------------------------
PASS=0; FAIL=0; WARN=0
green() { printf "\033[32m%s\033[0m" "$1"; }
red()   { printf "\033[31m%s\033[0m" "$1"; }
yellow(){ printf "\033[33m%s\033[0m" "$1"; }
have_jq() { command -v jq >/dev/null 2>&1; }

die() { echo "ERROR: $*" >&2; exit 1; }

# status_of METHOD URL [TOKEN] [JSON_BODY] -> prints HTTP status code
status_of() {
  local method="$1" url="$2" token="${3:-}" body="${4:-}"
  local args=(-s -o /dev/null -w "%{http_code}" -X "$method" "$url")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  if [[ -n "$body" ]]; then args+=(-H "Content-Type: application/json" -d "$body"); fi
  curl "${args[@]}"
}

# body_of METHOD URL [TOKEN] [JSON_BODY] -> prints response body
body_of() {
  local method="$1" url="$2" token="${3:-}" body="${4:-}"
  local args=(-s -X "$method" "$url")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  if [[ -n "$body" ]]; then args+=(-H "Content-Type: application/json" -d "$body"); fi
  curl "${args[@]}"
}

# assert NAME EXPECTED_REGEX ACTUAL
assert() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" =~ $expected ]]; then
    echo "  [$(green PASS)] $name (got $actual, expected $expected)"; ((PASS++))
  else
    echo "  [$(red FAIL)] $name (got $actual, expected $expected)"; ((FAIL++))
  fi
}

warn() { echo "  [$(yellow REVIEW)] $1"; ((WARN++)); }

mint_token() {
  local email="$1" pass="$2"
  local resp
  resp=$(curl -s -X POST \
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\",\"password\":\"${pass}\",\"returnSecureToken\":true}")
  if have_jq; then
    local t; t=$(echo "$resp" | jq -r '.idToken // empty')
    [[ -n "$t" ]] || { echo "    (token mint failed: $(echo "$resp" | jq -rc '.error.message // .'))" >&2; return 1; }
    echo "$t"
  else
    echo "$resp" | sed -n 's/.*"idToken": *"\([^"]*\)".*/\1/p'
  fi
}

# ----------------------------------------------------------------------------
# Pre-flight — prompt for anything not already provided via env vars
# ----------------------------------------------------------------------------
# prompt_if_empty VAR_NAME "Prompt text"            -> visible input
# prompt_if_empty VAR_NAME "Prompt text" secret     -> hidden input (passwords)
prompt_if_empty() {
  local var="$1" label="$2" secret="${3:-}" value
  [[ -n "${!var}" ]] && return            # already set via env — keep it
  if [[ ! -t 0 ]]; then die "$var is not set and there's no terminal to prompt on. Pass it via env."; fi
  if [[ "$secret" == "secret" ]]; then
    read -rs -p "$label: " value; echo
  else
    read -r  -p "$label: " value
  fi
  printf -v "$var" '%s' "$value"          # assign back into the named variable
}

echo "Enter test-account details (leave nothing blank for the four required ones):"
prompt_if_empty EMAIL_A    "User A email"
prompt_if_empty PASSWORD_A "User A password" secret
prompt_if_empty EMAIL_B    "User B email"
prompt_if_empty PASSWORD_B "User B password" secret
# Optional — press Return to skip and the related test is skipped.
prompt_if_empty A_ENTRY_ID "User A's insight id for the IDOR test (optional, Return to skip)"
echo

[[ -n "$EMAIL_A" && -n "$PASSWORD_A" && -n "$EMAIL_B" && -n "$PASSWORD_B" ]] \
  || die "All four of EMAIL_A/PASSWORD_A/EMAIL_B/PASSWORD_B are required."
have_jq || echo "(jq not found — identity-spoofing verdict will be manual; status-code tests still run)"

echo "Base: $BASE"
echo "Minting tokens…"
TOKEN_A=$(mint_token "$EMAIL_A" "$PASSWORD_A") || die "Could not mint token for A"
TOKEN_B=$(mint_token "$EMAIL_B" "$PASSWORD_B") || die "Could not mint token for B"
echo "  ok."
echo

# ----------------------------------------------------------------------------
# Step 1 — Token verification
# ----------------------------------------------------------------------------
echo "Step 1: token verification on /api/auth/me"
assert "no token rejected"      '^(401|403)$' "$(status_of GET "$BASE/api/auth/me")"
assert "garbage token rejected" '^(401|403)$' "$(status_of GET "$BASE/api/auth/me" "not.a.real.token")"
assert "valid token accepted"   '^200$'       "$(status_of GET "$BASE/api/auth/me" "$TOKEN_A")"
echo

# ----------------------------------------------------------------------------
# Step 2 — Identity must come from the token, NOT the request body
# ----------------------------------------------------------------------------
echo "Step 2: identity-from-token (register as A while claiming B's identity)"
ME_A=$(body_of GET "$BASE/api/auth/me" "$TOKEN_A")
SPOOF=$(body_of POST "$BASE/api/auth/register" "$TOKEN_A" \
  "{\"firebaseUid\":\"SPOOFED-UID-12345\",\"email\":\"${EMAIL_B}\",\"fullName\":\"Mallory\"}")
if have_jq; then
  me_email=$(echo "$ME_A" | jq -r '.data.email // .email // empty')
  spoof_email=$(echo "$SPOOF" | jq -r '.data.email // .email // empty')
  if [[ -n "$spoof_email" && "$spoof_email" == "$EMAIL_B" ]]; then
    echo "  [$(red FAIL)] server accepted B's email from the body (returned $spoof_email)"; ((FAIL++))
  elif [[ -n "$spoof_email" && "$spoof_email" == "$me_email" ]]; then
    echo "  [$(green PASS)] server ignored body, kept A's identity ($me_email)"; ((PASS++))
  else
    warn "inconclusive — inspect responses manually:"
    echo "        /me   -> $ME_A"
    echo "        spoof -> $SPOOF"
  fi
else
  warn "inspect these manually — the spoof response must NOT be tied to $EMAIL_B / SPOOFED-UID:"
  echo "        /me   -> $ME_A"
  echo "        spoof -> $SPOOF"
fi
echo

# ----------------------------------------------------------------------------
# Step 3 — email_verified enforced (optional)
# ----------------------------------------------------------------------------
echo "Step 3: unverified-email enforcement"
if [[ -n "$EMAIL_UNVERIFIED" && -n "$PASSWORD_UNVERIFIED" ]]; then
  TOKEN_U=$(mint_token "$EMAIL_UNVERIFIED" "$PASSWORD_UNVERIFIED") \
    && assert "unverified user blocked" '^(401|403)$' "$(status_of GET "$BASE/api/auth/me" "$TOKEN_U")" \
    || warn "could not mint unverified token (check the credentials)"
else
  warn "skipped — set EMAIL_UNVERIFIED/PASSWORD_UNVERIFIED (an account that never clicked the verify link)"
fi
echo

# ----------------------------------------------------------------------------
# Step 4 — Per-resource ownership (IDOR): B must not mutate A's entry
# ----------------------------------------------------------------------------
echo "Step 4: IDOR — User B acting on User A's insight"
if [[ -n "$A_ENTRY_ID" ]]; then
  # The app edits with PATCH (EditEntryView.swift), not PUT — using the wrong
  # method returns 405 and never reaches the ownership check.
  assert "B cannot EDIT A's entry"   '^(403|404)$' \
    "$(status_of PATCH "$BASE/api/insights/$A_ENTRY_ID" "$TOKEN_B" \
       '{"comment":"hijacked-by-B","isPublic":true,"starRating":1,"attributeRatings":[]}')"
  assert "B cannot DELETE A's entry" '^(403|404)$' \
    "$(status_of DELETE "$BASE/api/insights/$A_ENTRY_ID" "$TOKEN_B")"
else
  warn "skipped — set A_ENTRY_ID to an insight id owned by User A"
fi
echo

# ----------------------------------------------------------------------------
# Step 5 — Admin authorization (assumes A and B are NOT admins)
# ----------------------------------------------------------------------------
echo "Step 5: admin endpoints reject a non-admin (User A)"
assert "non-admin GET /api/admin/photos blocked"  '^(401|403)$' \
  "$(status_of GET "$BASE/api/admin/photos?page=1" "$TOKEN_A")"
assert "non-admin POST photo-of-the-week blocked" '^(401|403)$' \
  "$(status_of POST "$BASE/api/admin/photo-of-the-week" "$TOKEN_A" '{"photoId":"test"}')"
echo

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
echo "----------------------------------------"
echo "Passed: $(green "$PASS")   Failed: $(red "$FAIL")   Needs review: $(yellow "$WARN")"
[[ "$FAIL" -eq 0 ]] || echo "$(red "One or more authorization checks FAILED — treat as a security bug.")"
exit $(( FAIL > 0 ? 1 : 0 ))

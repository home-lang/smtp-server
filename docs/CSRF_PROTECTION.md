# CSRF Protection Guide

## Overview

Cross-Site Request Forgery (CSRF) protection has been implemented for all state-changing API operations in the SMTP server REST API.

## How It Works

### Token Lifecycle

1. **Token Generation**: Client requests a CSRF token via GET /api/csrf-token
2. **Token Storage**: Client stores token (in memory, session storage, etc.)
3. **Token Usage**: Client includes token in X-CSRF-Token header for POST/PUT/DELETE requests
4. **Token Validation**: Server validates token and consumes it (one-time use)
5. **Token Expiration**: Tokens expire after 1 hour if unused

### Security Features

- **Cryptographically Random**: 32-byte random tokens
- **One-Time Use**: Tokens are consumed after validation
- **Time-Limited**: 1-hour expiration (configurable)
- **Thread-Safe**: Concurrent request handling
- **Automatic Cleanup**: Expired tokens removed automatically

## API Usage

### Step 1: Get CSRF Token

```bash
curl -X GET http://localhost:8080/api/csrf-token
```

**Response**:
```json
{
  "token": "Abc123XyzRandomToken..."
}
```

### Step 2: Use Token in Request

Include the token in the `X-CSRF-Token` header:

```bash
curl -X POST http://localhost:8080/api/users \
  -H "X-CSRF-Token: Abc123XyzRandomToken..." \
  -H "Content-Type: application/json" \
  -d '{
    "username": "newuser",
    "password": "securepassword",
    "email": "user@example.com"
  }'
```

### Protected Endpoints

All state-changing operations require CSRF tokens:

**POST Endpoints**:
- `POST /api/users` - Create user
- `POST /api/filters` - Create filter rule
- `POST /api/search/rebuild` - Rebuild search index

**PUT Endpoints**:
- `PUT /api/users/{username}` - Update user
- `PUT /api/config` - Update configuration

**DELETE Endpoints**:
- `DELETE /api/users/{username}` - Delete user
- `DELETE /api/filters/{id}` - Delete filter

**Unprotected Endpoints** (no token required):
- All GET requests
- `GET /api/csrf-token` - Token generation endpoint

## JavaScript Example

### Vanilla JavaScript

```javascript
// Fetch CSRF token
async function getCSRFToken() {
  const response = await fetch('http://localhost:8080/api/csrf-token');
  const data = await response.json();
  return data.token;
}

// Create user with CSRF protection
async function createUser(username, password, email) {
  const token = await getCSRFToken();

  const response = await fetch('http://localhost:8080/api/users', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': token
    },
    body: JSON.stringify({ username, password, email })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Request failed');
  }

  return await response.json();
}

// Usage
try {
  await createUser('john', 'secure123', 'john@example.com');
  console.log('User created successfully');
} catch (error) {
  console.error('Failed to create user:', error.message);
}
```

### React Hook Example

```javascript
import { useState, useCallback } from 'react';

function useCSRF() {
  const [token, setToken] = useState(null);

  const fetchToken = useCallback(async () => {
    const response = await fetch('http://localhost:8080/api/csrf-token');
    const data = await response.json();
    setToken(data.token);
    return data.token;
  }, []);

  const makeRequest = useCallback(async (url, options = {}) => {
    const csrfToken = token || await fetchToken();

    const response = await fetch(url, {
      ...options,
      headers: {
        ...options.headers,
        'X-CSRF-Token': csrfToken
      }
    });

    if (response.status === 403) {
      // Token expired or invalid, retry with new token
      const newToken = await fetchToken();
      return fetch(url, {
        ...options,
        headers: {
          ...options.headers,
          'X-CSRF-Token': newToken
        }
      });
    }

    return response;
  }, [token, fetchToken]);

  return { fetchToken, makeRequest };
}

// Usage in component
function UserManagement() {
  const { makeRequest } = useCSRF();

  const handleCreateUser = async (userData) => {
    try {
      const response = await makeRequest('/api/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(userData)
      });

      if (response.ok) {
        console.log('User created');
      }
    } catch (error) {
      console.error('Error:', error);
    }
  };

  return (
    // ... component JSX
  );
}
```

### Axios Example

```javascript
import axios from 'axios';

// Create axios instance with CSRF interceptor
const api = axios.create({
  baseURL: 'http://localhost:8080'
});

// Request interceptor to add CSRF token
api.interceptors.request.use(async (config) => {
  // Skip token for GET requests
  if (config.method !== 'get') {
    try {
      const { data } = await axios.get('http://localhost:8080/api/csrf-token');
      config.headers['X-CSRF-Token'] = data.token;
    } catch (error) {
      console.error('Failed to get CSRF token:', error);
      throw error;
    }
  }
  return config;
});

// Response interceptor to handle 403 errors
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    if (error.response?.status === 403) {
      // Token invalid, retry once with new token
      const originalRequest = error.config;

      if (!originalRequest._retry) {
        originalRequest._retry = true;

        const { data } = await axios.get('http://localhost:8080/api/csrf-token');
        originalRequest.headers['X-CSRF-Token'] = data.token;

        return api(originalRequest);
      }
    }
    return Promise.reject(error);
  }
);

// Usage
async function createUser(userData) {
  const response = await api.post('/api/users', userData);
  return response.data;
}
```

## Error Handling

### 403 Forbidden

When CSRF token is missing or invalid:

```json
{
  "error": "Invalid or missing CSRF token"
}
```

**Causes**:
- Token not included in request
- Token already used (one-time use)
- Token expired (> 1 hour old)
- Token malformed

**Solution**:
- Fetch a new token via GET /api/csrf-token
- Retry the request with the new token

## Best Practices

### Do's ✅

1. **Fetch Fresh Tokens**: Get a new token for each operation
2. **Store Securely**: Keep tokens in memory, not localStorage (XSS risk)
3. **Handle Errors**: Implement retry logic for 403 errors
4. **Single-Page Apps**: Fetch token on page load or before first state-changing operation
5. **Mobile Apps**: Include token in all API calls that modify state

### Don'ts ❌

1. **Don't Reuse Tokens**: Tokens are single-use only
2. **Don't Store in Cookies**: Use headers, not cookies
3. **Don't Skip Validation**: Always include token for POST/PUT/DELETE
4. **Don't Hardcode Tokens**: Always fetch dynamically
5. **Don't Store in localStorage**: XSS vulnerability

## Configuration

### Server-Side Configuration

The CSRF manager can be configured in `src/api/api.zig`:

```zig
pub const CSRFManager = struct {
    token_lifetime_seconds: i64,  // Default: 3600 (1 hour)
    // ... other fields
};
```

To change token lifetime:
```zig
var csrf_manager = csrf_mod.CSRFManager.init(allocator);
csrf_manager.token_lifetime_seconds = 7200; // 2 hours
```

## Testing

### Manual Testing with curl

```bash
# 1. Get token
TOKEN=$(curl -s http://localhost:8080/api/csrf-token | jq -r '.token')

# 2. Use token
curl -X POST http://localhost:8080/api/users \
  -H "X-CSRF-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"pass","email":"test@example.com"}'

# 3. Try reusing token (should fail)
curl -X POST http://localhost:8080/api/users \
  -H "X-CSRF-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"test2","password":"pass","email":"test2@example.com"}'
# Response: {"error":"Invalid or missing CSRF token"}
```

### Automated Testing

```javascript
// Jest/Vitest test example
describe('CSRF Protection', () => {
  it('should reject request without CSRF token', async () => {
    const response = await fetch('/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'test' })
    });

    expect(response.status).toBe(403);
  });

  it('should accept request with valid CSRF token', async () => {
    // Get token
    const tokenRes = await fetch('/api/csrf-token');
    const { token } = await tokenRes.json();

    // Use token
    const response = await fetch('/api/users', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': token
      },
      body: JSON.stringify({
        username: 'test',
        password: 'pass',
        email: 'test@example.com'
      })
    });

    expect(response.ok).toBe(true);
  });

  it('should reject reused token', async () => {
    const tokenRes = await fetch('/api/csrf-token');
    const { token } = await tokenRes.json();

    // First request succeeds
    await fetch('/api/users', {
      method: 'POST',
      headers: { 'X-CSRF-Token': token },
      body: JSON.stringify({ username: 'test1' })
    });

    // Second request with same token fails
    const response = await fetch('/api/users', {
      method: 'POST',
      headers: { 'X-CSRF-Token': token },
      body: JSON.stringify({ username: 'test2' })
    });

    expect(response.status).toBe(403);
  });
});
```

## Migration Guide

### For Existing Clients

If you have existing API clients, follow these steps:

1. **Update API calls** to fetch CSRF tokens before state-changing operations
2. **Add X-CSRF-Token header** to all POST/PUT/DELETE requests
3. **Implement retry logic** for 403 errors (fetch new token and retry)
4. **Test thoroughly** with the updated implementation

### Temporary Bypass (Not Recommended)

For testing or gradual migration, you can temporarily disable CSRF protection:

```zig
// In src/api/api.zig - NOT RECOMMENDED FOR PRODUCTION
fn validateCSRFToken(self: *APIServer, request: []const u8) !bool {
    // TEMPORARY: Disable CSRF validation
    _ = self;
    _ = request;
    return true;  // WARNING: Disables protection!
}
```

**Never deploy this to production!**

## Security Considerations

### What CSRF Protection Prevents

✅ **Prevents**:
- Unauthorized state changes from malicious websites
- Forged requests from third-party domains
- One-click attacks exploiting authenticated sessions

### What CSRF Protection Doesn't Prevent

❌ **Does NOT prevent**:
- XSS (Cross-Site Scripting) attacks
- SQL injection
- Man-in-the-middle attacks
- Credential stuffing
- Brute force attacks

### Additional Security Measures

For comprehensive security, also implement:
- Content Security Policy (CSP)
- HTTPS/TLS encryption
- Input validation
- Rate limiting
- Strong authentication

## Troubleshooting

### Common Issues

**Problem**: 403 error on all requests
**Solution**: Ensure you're fetching and including the CSRF token

**Problem**: Token seems to expire immediately
**Solution**: Check that you're not reusing tokens (they're single-use)

**Problem**: CORS errors when fetching token
**Solution**: Configure CORS headers on the server

**Problem**: Token validation fails intermittently
**Solution**: Check for race conditions in token fetching/usage

### Debug Logging

Enable debug logging to troubleshoot CSRF issues:

```zig
// In src/auth/csrf.zig
std.log.debug("Token generated: {s}", .{token});
std.log.debug("Token validated: {s}, valid: {}", .{token, valid});
```

## FAQ

**Q: Do I need CSRF protection for GET requests?**
A: No, CSRF protection is only required for state-changing operations (POST/PUT/DELETE).

**Q: Can I use the same token for multiple requests?**
A: No, tokens are single-use. Fetch a new token for each operation.

**Q: How long are tokens valid?**
A: Tokens expire after 1 hour (configurable).

**Q: What if my token expires during a long form fill?**
A: Implement a refresh mechanism that fetches a new token before submission.

**Q: Is this compliant with OWASP guidelines?**
A: Yes, this implementation follows OWASP CSRF prevention guidelines.

**Q: Can I use cookies instead of headers?**
A: No, the current implementation uses header-based tokens for better security.

## References

- [OWASP CSRF Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)
- [RFC 6749 - OAuth 2.0 State Parameter](https://tools.ietf.org/html/rfc6749#section-10.12)
- [SameSite Cookie Attribute](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie/SameSite)

---

For questions or issues, please refer to the main project documentation or create an issue on GitHub.

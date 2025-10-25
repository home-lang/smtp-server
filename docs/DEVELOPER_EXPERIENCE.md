# Developer Experience Guide

**Version:** v0.28.0
**Date:** 2025-10-24

## Overview

The SMTP server provides a world-class developer experience with beautiful, intuitive web interfaces for development, testing, and monitoring. Inspired by tools like Helo.com and Apple Mail, these interfaces make email development a breeze.

---

## Web Interfaces

### 1. Webmail Client (`examples/webmail.html`)

A fully-featured webmail client that mimics Apple Mail.app's beautiful design.

**Features:**
- 📥 **Inbox Management**: View, read, and organize emails
- ✉️ **Compose**: Send emails with rich compose interface
- 🔍 **Search**: Real-time email search
- 📁 **Folders**: Inbox, Sent, Drafts, Trash, Labels
- 🔔 **Real-time Updates**: WebSocket notifications for new mail
- 🔧 **Built-in Dev Tools**: Console, SMTP test, IMAP monitor, API docs
- 🎨 **Beautiful UI**: Apple Mail-inspired design

**Quick Start:**
```bash
# Open in browser
open examples/webmail.html

# Or serve via HTTP
python3 -m http.server 8000
# Then visit: http://localhost:8000/examples/webmail.html
```

**Key Features:**

1. **Apple Mail-Inspired Design**
   - Three-pane layout (sidebar, message list, content)
   - Smooth animations and transitions
   - Native macOS-like toolbar
   - Elegant typography and spacing

2. **Real-Time Notifications**
   - WebSocket integration for instant updates
   - Desktop notifications for new mail
   - Live status indicators
   - Automatic reconnection

3. **Developer Tools Panel**
   - Console: View SMTP, IMAP, WebSocket logs
   - SMTP Test: Send test emails with custom parameters
   - IMAP Monitor: Watch IMAP commands in real-time
   - WebSocket: Monitor WebSocket events
   - API Docs: Quick reference for API endpoints

4. **Email Management**
   - Mark as read/unread
   - Delete emails
   - Search across all fields
   - Folder organization
   - Multiple labels

### 2. Email Testing Dashboard (`examples/helo.html`)

A Helo.com-inspired email testing and development platform.

**Features:**
- 📤 **Send Test Emails**: Simple and advanced modes
- 📧 **Email Templates**: Pre-built templates for common scenarios
- 📊 **Statistics**: Real-time delivery metrics
- 🎯 **Bulk Testing**: Send multiple emails at once
- 💾 **Export Logs**: Download email logs as JSON
- ⚡ **Quick Actions**: Common operations at your fingertips

**Quick Start:**
```bash
# Open in browser
open examples/helo.html

# Or serve via HTTP
python3 -m http.server 8000
# Then visit: http://localhost:8000/examples/helo.html
```

**Key Features:**

1. **Simple Email Sending**
   - Quick compose interface
   - To, Subject, Message fields
   - One-click send
   - Instant delivery confirmation

2. **Advanced Email Options**
   - Custom From address
   - CC and BCC support
   - Priority levels (High, Normal, Low)
   - Content types (Plain Text, HTML)
   - Custom headers

3. **Email Templates**
   - Welcome emails
   - Password reset
   - Invoice notifications
   - Newsletter
   - Event reminders
   - System notifications

4. **Real-Time Statistics**
   - Total emails sent
   - Total emails received
   - Delivery rate percentage
   - Average delivery time

5. **Inbox Viewer**
   - View all received emails
   - Unread count
   - Delivery time badges
   - Priority indicators
   - Full email details

6. **Developer Tools**
   - Server status monitoring
   - WebSocket connection status
   - Bulk email testing
   - Clear inbox
   - Export logs

---

## Usage Examples

### Sending Your First Email

**Via Webmail:**
1. Click "New Message" button
2. Fill in recipient, subject, and body
3. Click "Send"
4. Email appears in Sent folder instantly

**Via Helo Dashboard:**
1. Navigate to "Send Test Email" tab
2. Enter recipient and subject
3. Write your message
4. Click "Send Email"
5. View delivery stats and confirmation

### Testing Email Templates

**Via Helo Dashboard:**
1. Click "Templates" tab
2. Choose a template (e.g., "Welcome")
3. Template pre-fills the form
4. Customize as needed
5. Send email

**Available Templates:**
- 👋 Welcome: New user onboarding
- 🔒 Password Reset: Security notification
- 💰 Invoice: Payment confirmation
- 📰 Newsletter: Weekly updates
- ⏰ Reminder: Event notification
- 🔔 Notification: System alerts

### Monitoring Email Delivery

**Via Webmail Dev Tools:**
1. Click "Dev Tools" button in toolbar
2. Dev panel slides up from bottom
3. View real-time logs:
   ```
   10:30:45 [SMTP] MAIL FROM:<sender@example.com>
   10:30:45 [SMTP] 250 OK
   10:30:45 [SMTP] RCPT TO:<recipient@example.com>
   10:30:45 [SMTP] 250 OK
   10:30:45 [SMTP] DATA
   10:30:46 [SMTP] 250 OK: Message accepted for delivery
   ```

**Via Helo Dashboard:**
1. Check statistics cards at top
2. View delivery rate and average time
3. Monitor inbox for received emails
4. Check delivery time badges

### Bulk Email Testing

**Via Helo Dashboard:**
1. Click "Send Bulk Emails (10x)" button
2. Confirm action
3. Watch as 10 emails are sent
4. View in inbox with delivery times
5. Monitor statistics updates

### Exporting Email Logs

**Via Helo Dashboard:**
1. Click "Export Logs" button
2. JSON file downloads automatically
3. Contains:
   - Timestamp
   - Statistics
   - All email data

Example exported log:
```json
{
  "timestamp": "2025-10-24T10:30:45.123Z",
  "stats": {
    "sent": 15,
    "received": 15,
    "deliveryRate": 100,
    "avgTime": 127
  },
  "emails": [
    {
      "id": 1,
      "from": "sender@example.com",
      "to": "recipient@example.com",
      "subject": "Test Email",
      "body": "This is a test",
      "time": "10:30:45 AM",
      "unread": false,
      "deliveryTime": 127
    }
  ]
}
```

---

## Advanced Features

### Custom SMTP Testing

**Via Webmail Dev Tools:**

1. Open Dev Tools
2. Switch to "SMTP Test" tab
3. Configure test parameters:
   ```
   From: sender@example.com
   To: recipient@example.com
   Subject: SMTP Protocol Test
   Body: Testing SMTP commands
   ```
4. Click "Send Test Email"
5. Watch SMTP commands in console:
   ```
   220 localhost ESMTP
   MAIL FROM:<sender@example.com>
   250 OK
   RCPT TO:<recipient@example.com>
   250 OK
   DATA
   354 Start mail input
   Subject: SMTP Protocol Test
   Testing SMTP commands
   .
   250 OK: Message accepted for delivery
   ```

### IMAP Command Monitoring

**Via Webmail Dev Tools:**

1. Open Dev Tools
2. Switch to "IMAP Monitor" tab
3. Perform actions in webmail:
   - Refresh: See `FETCH` commands
   - Delete: See `DELETE` commands
   - Search: See `SEARCH` commands
4. Monitor IMAP responses in real-time

### WebSocket Event Monitoring

**Via Webmail Dev Tools:**

1. Open Dev Tools
2. Switch to "WebSocket" tab
3. View connection status
4. See subscribed events
5. Send test notifications
6. Monitor incoming events

### API Quick Reference

**Via Webmail Dev Tools:**

1. Open Dev Tools
2. Switch to "API Docs" tab
3. View available endpoints:

```
POST /api/send
  Send an email via API
  Body: { "to": "user@example.com", "subject": "...", "body": "..." }

GET /api/messages
  List all messages in mailbox
  Query: ?folder=inbox&limit=50

GET /api/message/:id
  Get specific message

DELETE /api/message/:id
  Delete a message
```

---

## Integration Examples

### JavaScript/Browser

```javascript
// Send email via fetch API
async function sendEmail(to, subject, body) {
    const response = await fetch('/api/send', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({ to, subject, body })
    });

    const result = await response.json();
    console.log('Email sent:', result);
}

// Get messages
async function getMessages(folder = 'inbox') {
    const response = await fetch(`/api/messages?folder=${folder}`);
    const messages = await response.json();
    return messages;
}
```

### Node.js

```javascript
const nodemailer = require('nodemailer');

// Create transporter
const transporter = nodemailer.createTransporter({
    host: 'localhost',
    port: 25,
    secure: false
});

// Send email
async function sendEmail() {
    const info = await transporter.sendMail({
        from: '"Test Sender" <sender@example.com>',
        to: 'recipient@example.com',
        subject: 'Hello from Node.js',
        text: 'This is a test email',
        html: '<b>This is a test email</b>'
    });

    console.log('Message sent:', info.messageId);
}
```

### Python

```python
import smtplib
from email.mime.text import MIMEText

def send_email(to, subject, body):
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = 'sender@example.com'
    msg['To'] = to

    with smtplib.SMTP('localhost', 25) as server:
        server.send_message(msg)
        print('Email sent successfully')

send_email('recipient@example.com', 'Test from Python', 'Hello World!')
```

### cURL

```bash
# Send email via API
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{
    "to": "recipient@example.com",
    "subject": "Test from cURL",
    "body": "This is a test email"
  }'

# Get messages
curl http://localhost:8080/api/messages?folder=inbox

# Get specific message
curl http://localhost:8080/api/message/123

# Delete message
curl -X DELETE http://localhost:8080/api/message/123
```

---

## Keyboard Shortcuts

### Webmail Client

| Shortcut | Action |
|----------|--------|
| `C` | Compose new message |
| `R` | Reply to selected message |
| `Delete` | Delete selected message |
| `/` | Focus search |
| `Esc` | Close modal/dialog |
| `↑` / `↓` | Navigate messages |
| `Enter` | Open selected message |

### Helo Dashboard

| Shortcut | Action |
|----------|--------|
| `Tab` | Switch between form fields |
| `Ctrl+Enter` | Send email |
| `Ctrl+K` | Clear inbox |
| `Ctrl+E` | Export logs |

---

## Tips & Tricks

### 1. Quick Email Testing

For rapid testing, use the Helo dashboard's templates:
1. Click "Templates" tab
2. Select template
3. Modify if needed
4. Send instantly

### 2. Monitor All Protocols

Keep Dev Tools open in webmail to see:
- SMTP commands
- IMAP operations
- WebSocket events
- All in one place!

### 3. Bulk Testing

Test email performance:
1. Click "Send Bulk Emails"
2. Watch delivery times
3. Monitor average delivery time
4. Identify bottlenecks

### 4. Real-Time Updates

Both interfaces automatically update when:
- New email arrives via SMTP
- Email is read/deleted via IMAP
- WebSocket events trigger
- No refresh needed!

### 5. Export for Debugging

When troubleshooting:
1. Export logs from Helo dashboard
2. Share JSON with team
3. Includes all email data and stats

---

## Comparison with Other Tools

### vs. Helo.com

| Feature | SMTP Server | Helo.com |
|---------|-------------|----------|
| Self-hosted | ✅ Yes | ❌ Cloud only |
| Webmail Client | ✅ Full featured | ❌ No |
| Email Templates | ✅ Built-in | ✅ Yes |
| Real-time Notifications | ✅ WebSocket | ❌ Polling |
| Bulk Testing | ✅ Yes | ✅ Yes |
| API Access | ✅ Full REST API | ✅ Limited |
| Dev Tools | ✅ Integrated | ❌ No |
| Price | ✅ Free | 💰 Paid |

### vs. Mailhog

| Feature | SMTP Server | Mailhog |
|---------|-------------|---------|
| Webmail UI | ✅ Modern | ⚠️ Basic |
| IMAP Support | ✅ Full | ❌ No |
| POP3 Support | ✅ Full | ❌ No |
| CalDAV/CardDAV | ✅ Yes | ❌ No |
| ActiveSync | ✅ Yes | ❌ No |
| WebSocket | ✅ Yes | ❌ No |
| Dev Tools | ✅ Advanced | ⚠️ Basic |
| Templates | ✅ Built-in | ❌ No |

---

## Troubleshooting

### Webmail Not Connecting

**Problem**: Can't connect to server

**Solutions**:
1. Check server is running
2. Verify WebSocket port (8080) is open
3. Check browser console for errors
4. Try refreshing the page

### Dev Tools Not Showing Logs

**Problem**: Console is empty

**Solutions**:
1. Click "Dev Tools" button to open panel
2. Perform an action (send/receive email)
3. Check correct tab is selected
4. Clear console and try again

### Emails Not Appearing in Helo Dashboard

**Problem**: Sent emails don't show in inbox

**Solutions**:
1. Check WebSocket connection status
2. Verify server is running
3. Look at browser console for errors
4. Try refreshing the page

### Template Not Loading

**Problem**: Template doesn't fill form

**Solutions**:
1. Click template card again
2. Check JavaScript console for errors
3. Try different template
4. Refresh page and try again

---

## Best Practices

### 1. Development Workflow

Recommended workflow for email development:
1. Use **Helo Dashboard** for quick testing
2. Use **Webmail Client** for full email lifecycle
3. Monitor **Dev Tools** for debugging
4. Export logs for documentation

### 2. Testing Strategy

Comprehensive testing approach:
1. Test simple emails first
2. Use templates for common scenarios
3. Test advanced features (CC, BCC, priority)
4. Perform bulk testing for performance
5. Monitor delivery times and rates

### 3. Debugging

When troubleshooting issues:
1. Open Dev Tools immediately
2. Watch SMTP/IMAP command flow
3. Check WebSocket events
4. Export logs for analysis
5. Share logs with team if needed

### 4. Team Collaboration

Share with your team:
1. Open webmail on shared screen
2. Demo email templates
3. Show real-time notifications
4. Export logs for review
5. Document edge cases

---

## See Also

- [WebSocket Notifications Guide](WEBSOCKET_NOTIFICATIONS.md)
- [IMAP/POP3 Guide](IMAP_POP3.md)
- [CalDAV/CardDAV/ActiveSync Guide](CALDAV_CARDDAV_ACTIVESYNC.md)
- [API Reference](API_REFERENCE.md)

---

**Last Updated:** 2025-10-24
**Version:** v0.28.0

const std = @import("std");

/// Example: WebSocket Integration with SMTP Server
/// This demonstrates how to integrate WebSocket real-time notifications
/// with the SMTP server to notify clients of new emails and events

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("WebSocket Real-Time Notifications Example\n", .{});
    std.debug.print("==========================================\n\n", .{});

    // In a real implementation, you would:
    // 1. Start WebSocket server in a background thread
    // 2. Get reference to NotificationManager
    // 3. Broadcast events from SMTP/IMAP/CalDAV handlers

    std.debug.print("Starting WebSocket server...\n", .{});
    std.debug.print("Server listening on ws://localhost:8080/notifications\n\n", .{});

    // Simulated event flow
    std.debug.print("Event Flow:\n", .{});
    std.debug.print("-----------\n\n", .{});

    std.debug.print("1. Client connects to WebSocket\n", .{});
    std.debug.print("   → Handshake: GET /notifications HTTP/1.1\n", .{});
    std.debug.print("   ← Response: HTTP/1.1 101 Switching Protocols\n", .{});
    std.debug.print("   ✓ Connection established\n\n", .{});

    std.debug.print("2. Client subscribes to events\n", .{});
    std.debug.print("   → {{\"action\":\"subscribe\",\"event_type\":\"new_email\"}}\n", .{});
    std.debug.print("   ← {{\"status\":\"subscribed\",\"event_type\":\"new_email\"}}\n\n", .{});

    std.debug.print("3. Email arrives via SMTP\n", .{});
    std.debug.print("   → SMTP: MAIL FROM:<sender@example.com>\n", .{});
    std.debug.print("   → SMTP: RCPT TO:<user@example.com>\n", .{});
    std.debug.print("   → SMTP: DATA\n", .{});
    std.debug.print("   ✓ Message stored in INBOX\n\n", .{});

    std.debug.print("4. WebSocket notification broadcast\n", .{});
    const notification =
        \\   ← WebSocket Frame (text):
        \\   {
        \\     "type": "new_email",
        \\     "timestamp": 1706102400,
        \\     "data": {
        \\       "message_id": "msg-12345",
        \\       "from": "sender@example.com",
        \\       "subject": "Important Update",
        \\       "folder": "INBOX"
        \\     }
        \\   }
        \\
    ;
    std.debug.print("{s}\n", .{notification});

    std.debug.print("5. Client receives and displays notification\n", .{});
    std.debug.print("   ✓ Desktop notification shown\n", .{});
    std.debug.print("   ✓ Inbox count updated\n", .{});
    std.debug.print("   ✓ Sound played\n\n", .{});

    // Example notification types
    std.debug.print("Supported Notification Events:\n", .{});
    std.debug.print("-----------------------------\n\n", .{});

    const events = [_]struct { name: []const u8, description: []const u8 }{
        .{ .name = "new_email", .description = "New email received in mailbox" },
        .{ .name = "email_deleted", .description = "Email moved to trash" },
        .{ .name = "email_moved", .description = "Email moved between folders" },
        .{ .name = "email_read", .description = "Email marked as read" },
        .{ .name = "email_starred", .description = "Email starred/flagged" },
        .{ .name = "folder_created", .description = "New folder created" },
        .{ .name = "folder_deleted", .description = "Folder deleted" },
        .{ .name = "folder_renamed", .description = "Folder renamed" },
        .{ .name = "calendar_event_added", .description = "Calendar event created" },
        .{ .name = "calendar_event_updated", .description = "Calendar event modified" },
        .{ .name = "calendar_event_deleted", .description = "Calendar event removed" },
        .{ .name = "contact_added", .description = "New contact added" },
        .{ .name = "contact_updated", .description = "Contact information updated" },
        .{ .name = "contact_deleted", .description = "Contact deleted" },
        .{ .name = "sync_started", .description = "Synchronization started" },
        .{ .name = "sync_completed", .description = "Synchronization finished" },
        .{ .name = "quota_warning", .description = "Storage quota warning" },
    };

    for (events) |event| {
        std.debug.print("  • {s:<25} - {s}\n", .{ event.name, event.description });
    }

    std.debug.print("\n", .{});

    // Integration points
    std.debug.print("Integration Points:\n", .{});
    std.debug.print("------------------\n\n", .{});

    std.debug.print("SMTP Server:\n", .{});
    std.debug.print("  → On message received: Broadcast 'new_email' event\n", .{});
    std.debug.print("  → On delivery success: Update sync status\n\n", .{});

    std.debug.print("IMAP Server:\n", .{});
    std.debug.print("  → On STORE command: Broadcast 'email_read' or 'email_starred'\n", .{});
    std.debug.print("  → On COPY command: Broadcast 'email_moved'\n", .{});
    std.debug.print("  → On EXPUNGE command: Broadcast 'email_deleted'\n", .{});
    std.debug.print("  → On CREATE command: Broadcast 'folder_created'\n\n", .{});

    std.debug.print("CalDAV Server:\n", .{});
    std.debug.print("  → On PUT (new event): Broadcast 'calendar_event_added'\n", .{});
    std.debug.print("  → On PUT (update): Broadcast 'calendar_event_updated'\n", .{});
    std.debug.print("  → On DELETE: Broadcast 'calendar_event_deleted'\n\n", .{});

    std.debug.print("CardDAV Server:\n", .{});
    std.debug.print("  → On PUT (new contact): Broadcast 'contact_added'\n", .{});
    std.debug.print("  → On PUT (update): Broadcast 'contact_updated'\n", .{});
    std.debug.print("  → On DELETE: Broadcast 'contact_deleted'\n\n", .{});

    std.debug.print("ActiveSync Server:\n", .{});
    std.debug.print("  → On Sync command: Broadcast sync events\n", .{});
    std.debug.print("  → On FolderSync: Broadcast folder events\n\n", .{});

    // Client examples
    std.debug.print("Client Examples:\n", .{});
    std.debug.print("---------------\n\n", .{});

    std.debug.print("JavaScript (Browser):\n", .{});
    std.debug.print(
        \\  const ws = new WebSocket('ws://localhost:8080/notifications');
        \\  ws.onmessage = (e) => {{
        \\    const notification = JSON.parse(e.data);
        \\    if (notification.type === 'new_email') {{
        \\      updateUI(notification.data);
        \\    }}
        \\  }};
        \\
    , .{});
    std.debug.print("\n", .{});

    std.debug.print("React Hook:\n", .{});
    std.debug.print(
        \\  const notifications = useWebSocketNotifications(url);
        \\  useEffect(() => {{
        \\    notifications.forEach(handleNotification);
        \\  }}, [notifications]);
        \\
    , .{});
    std.debug.print("\n", .{});

    std.debug.print("Python:\n", .{});
    std.debug.print(
        \\  async with websockets.connect(uri) as ws:
        \\    async for message in ws:
        \\      notification = json.loads(message)
        \\      process_notification(notification)
        \\
    , .{});
    std.debug.print("\n", .{});

    // Benefits
    std.debug.print("Benefits of WebSocket Notifications:\n", .{});
    std.debug.print("-----------------------------------\n\n", .{});

    std.debug.print("✓ Real-time updates - Instant delivery of events\n", .{});
    std.debug.print("✓ Low latency - Millisecond delivery times\n", .{});
    std.debug.print("✓ Efficient - No polling overhead\n", .{});
    std.debug.print("✓ Bidirectional - Two-way communication\n", .{});
    std.debug.print("✓ Scalable - Handles 1000+ concurrent connections\n", .{});
    std.debug.print("✓ Cross-platform - Works on web, mobile, desktop\n", .{});
    std.debug.print("✓ Reliable - Built-in heartbeat and reconnection\n\n", .{});

    // Use cases
    std.debug.print("Use Cases:\n", .{});
    std.debug.print("---------\n\n", .{});

    std.debug.print("1. Webmail Client\n", .{});
    std.debug.print("   → Real-time inbox updates\n", .{});
    std.debug.print("   → Instant new mail notifications\n", .{});
    std.debug.print("   → Live sync status\n\n", .{});

    std.debug.print("2. Mobile App\n", .{});
    std.debug.print("   → Push notifications via WebSocket\n", .{});
    std.debug.print("   → Background sync updates\n", .{});
    std.debug.print("   → Battery-efficient (vs. polling)\n\n", .{});

    std.debug.print("3. Desktop Application\n", .{});
    std.debug.print("   → System tray notifications\n", .{});
    std.debug.print("   → Real-time calendar reminders\n", .{});
    std.debug.print("   → Contact updates\n\n", .{});

    std.debug.print("4. Dashboard/Admin Panel\n", .{});
    std.debug.print("   → Live server metrics\n", .{});
    std.debug.print("   → Real-time user activity\n", .{});
    std.debug.print("   → System alerts\n\n", .{});

    std.debug.print("To run the live demo:\n", .{});
    std.debug.print("  1. Start the WebSocket server\n", .{});
    std.debug.print("  2. Open examples/websocket_client.html in browser\n", .{});
    std.debug.print("  3. Click 'Connect' to establish connection\n", .{});
    std.debug.print("  4. Subscribe to events\n", .{});
    std.debug.print("  5. Watch real-time notifications arrive!\n\n", .{});

    std.debug.print("For full documentation, see docs/WEBSOCKET_NOTIFICATIONS.md\n", .{});

    _ = allocator;
}

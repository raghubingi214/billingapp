import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/notification_repository.dart';
import '../data/supabase_notification_repository.dart';
import '../../sales/presentation/sales_screen.dart';
import '../../purchases/presentation/purchase_detail_screen.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => SupabaseNotificationRepository(ref.watch(supabaseClientProvider)),
);

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key, required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with WidgetsBindingObserver {
  List<BusinessNotification> rows = [];
  bool busy = false, more = false, unreadOnly = false;
  String? openingId;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load(reset: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      if (reset) {
        rows = [];
        more = false;
      }
    });
    try {
      final page = await ref
          .read(notificationRepositoryProvider)
          .page(widget.organizationId, rows.length, unreadOnly);
      if (mounted) {
        setState(() {
          rows = [...rows, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load notifications. Retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(BusinessNotification notification) async {
    if (busy || openingId != null) return;
    setState(() => openingId = notification.id);
    try {
      await ref
          .read(notificationRepositoryProvider)
          .markRead(widget.organizationId, notification.id);
      if (!mounted) return;
      if (notification.entityType == 'sales_invoices') {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => SalesDetailScreen(
              organizationId: widget.organizationId,
              invoiceId: notification.entityId,
            ),
          ),
        );
      } else if (notification.entityType == 'purchases') {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => PurchaseDetailScreen(
              organizationId: widget.organizationId,
              purchaseId: notification.entityId,
              canPay: false,
            ),
          ),
        );
      }
      if (mounted) load(reset: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification unavailable. Your business access may have changed.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        IconButton(
          tooltip: 'Refresh notifications',
          onPressed: busy || openingId != null ? null : () => load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          if (openingId == null) await load(reset: true);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              title: const Text('Unread only'),
              value: unreadOnly,
              onChanged: busy || openingId != null
                  ? null
                  : (value) {
                      setState(() => unreadOnly = value);
                      load(reset: true);
                    },
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(
                onPressed: openingId != null ? null : () => load(),
                child: Text(error!),
              ),
            if (!busy && error == null && rows.isEmpty)
              const ListTile(title: Text('No notifications')),
            for (final notification in rows)
              Card(
                child: ListTile(
                  leading: openingId == notification.id
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(),
                        )
                      : Icon(
                          notification.read
                              ? Icons.drafts_outlined
                              : Icons.mark_email_unread_outlined,
                        ),
                  title: Text(notification.title),
                  subtitle: Text(notification.body),
                  onTap: busy || openingId != null
                      ? null
                      : () => open(notification),
                ),
              ),
            if (more && !busy && error == null)
              TextButton(
                onPressed: () => load(),
                child: const Text('Load more'),
              ),
          ],
        ),
      ),
    ),
  );
}

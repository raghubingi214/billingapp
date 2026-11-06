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
  bool busy = false, more = true, unreadOnly = false;
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
    setState(() => busy = true);
    try {
      if (reset) rows = [];
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
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              title: const Text('Unread only'),
              value: unreadOnly,
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() => unreadOnly = value);
                      load(reset: true);
                    },
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: () => load(), child: Text(error!)),
            if (!busy && rows.isEmpty)
              const ListTile(title: Text('No notifications')),
            for (final notification in rows)
              Card(
                child: ListTile(
                  leading: Icon(
                    notification.read
                        ? Icons.drafts_outlined
                        : Icons.mark_email_unread_outlined,
                  ),
                  title: Text(notification.title),
                  subtitle: Text(notification.body),
                  onTap: () => open(notification),
                ),
              ),
            if (more && !busy)
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

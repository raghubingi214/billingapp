import 'dart:convert';
import 'package:flutter/services.dart';

class SuggestedPlanTemplates {
  Future<List<Map<String, String>>> load() async {
    final config =
        jsonDecode(await rootBundle.loadString('config/proposed-plans.json'))
            as Map<String, dynamic>;
    return [
      for (final raw in config['plans'] as List)
        {
          'code': raw['code'] as String,
          'name': raw['name'] as String,
          'billing_interval': 'month',
          'price_inr': '${raw['monthly_price']}',
          'monthly_invoice_limit': '${raw['monthly_invoice_limit']}',
          'staff_limit': '${raw['user_limit']}',
          'location_limit': '${raw['location_limit']}',
          'report_types': (raw['report_types'] as List).join(','),
          'monthly_reminder_limit': '0',
        },
    ];
  }
}

import 'dart:convert';
import 'package:flutter/services.dart';

class SuggestedPlanTemplates {
  Future<List<Map<String, String>>> load() async {
    final config =
        jsonDecode(await rootBundle.loadString('config/proposed-plans.json'))
            as Map<String, dynamic>;
    return [
      for (final raw in config['paid_plans'] as List)
        for (final interval in ['month', 'year'])
          {
            'code': '${raw['code']}_$interval',
            'name':
                '${raw['code'] == 'starter' ? 'Starter' : 'Business'} ${interval == 'month' ? 'Monthly' : 'Annual'}',
            'billing_interval': interval,
            'price_inr':
                '${raw[interval == 'month' ? 'monthly_price' : 'annual_price']}',
            'monthly_invoice_limit': '${raw['monthly_invoice_limit']}',
            'staff_limit': '${raw['user_limit']}',
            'location_limit': '${raw['location_limit']}',
            'trial_invoice_limit': '',
            // Messaging allowance requires an explicit administrator decision.
            'monthly_reminder_limit': '',
          },
    ];
  }
}

import 'package:flutter/material.dart';

import '../../../core/widgets/app_scope.dart';

class AgentAccountStatusScreen extends StatelessWidget {
  const AgentAccountStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.of(context).controller.profile;
    final bool suspended = profile?.agentAccountStatus == "suspended";

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        suspended
                            ? "Akaunti imesimamishwa"
                            : "Akaunti yako haijawashwa kwa sasa.",
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        suspended
                            ? "Wasiliana na KODIMALI ili kuthibitisha hali ya akaunti yako."
                            : "Usajili wako umepokelewa, lakini admin bado anahitaji kuidhinisha access ya agent kabla hujaingia kwenye workspace.",
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Kwa msaada zaidi, piga au WhatsApp 0684684972 au 0628621737.",
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () =>
                              AppScope.of(context).controller.signOut(),
                          child: const Text("Toka"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

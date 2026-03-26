import 'package:flutter/material.dart';

import '../community/community_page.dart';

class CreateOfferPage extends StatelessWidget {
  const CreateOfferPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonPage(
      title: 'Offri',
      description:
          'La prossima tappa qui e` la creazione offerta da mobile, e poi la sostituzione della mappa con Google Maps / Places.',
      icon: Icons.add_location_alt_outlined,
    );
  }
}

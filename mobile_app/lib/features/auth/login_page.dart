import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import 'auth_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final ok = await widget.authController.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted || ok) {
      return;
    }

    final message = widget.authController.errorMessage ?? 'Login non riuscito.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        final busy = widget.authController.isBusy;
        return Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      children: [
                        const BrandHeroCard(
                          eyebrow: 'APP MOBILE',
                          title: 'Entra e inizia a muoverti nella community.',
                          subtitle:
                              'Questa e\' la versione Android utenti di ApprofittOffro. Backend e admin restano sul sistema web attuale.',
                        ),
                        const SizedBox(height: 18),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Accedi',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Usa le stesse credenziali che hai gia\' sul sito.',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      hintText: 'nome@email.it',
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Inserisci la tua email.';
                                      }
                                      if (!value.contains('@')) {
                                        return 'Email non valida.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Password',
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Inserisci la password.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton(
                                    onPressed: busy ? null : _submit,
                                    child: busy
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Accedi'),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                          color: AppTheme.cardBorder),
                                    ),
                                    child: const Text(
                                      'Registrazione, recupero password e modifica profilo arrivano nel prossimo blocco Flutter.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

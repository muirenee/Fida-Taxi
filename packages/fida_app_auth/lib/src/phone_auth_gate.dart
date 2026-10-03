import 'package:fida_api/fida_api.dart';
import 'package:fida_design_system/fida_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef FidaCoreApiFactory =
    FidaCoreApi Function(FidaApiConfiguration configuration);

typedef AuthenticatedBuilder =
    Widget Function(
      BuildContext context,
      AuthSession session,
      VoidCallback signOut,
    );

final class PhoneAuthGate extends StatefulWidget {
  const PhoneAuthGate({
    required this.appName,
    required this.expectedRole,
    required this.authenticatedBuilder,
    this.apiFactory,
    this.initialBaseUrl = const String.fromEnvironment(
      'FIDA_API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000/api/v1',
    ),
    super.key,
  });

  final String appName;
  final AuthRole expectedRole;
  final AuthenticatedBuilder authenticatedBuilder;
  final FidaCoreApiFactory? apiFactory;
  final String initialBaseUrl;

  @override
  State<PhoneAuthGate> createState() => _PhoneAuthGateState();
}

final class _PhoneAuthGateState extends State<PhoneAuthGate> {
  late final TextEditingController _serverController;
  final TextEditingController _phoneController = TextEditingController(
    text: '+250',
  );
  final TextEditingController _codeController = TextEditingController();

  FidaCoreApi? _api;
  PhoneLoginChallenge? _challenge;
  AuthSession? _session;
  String? _errorMessage;
  bool _isBusy = false;

  bool get _hasChallenge => _challenge?.challengeId != null;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.initialBaseUrl);
  }

  @override
  void dispose() {
    _api?.close();
    _serverController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your phone number in international format.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      final configuration = FidaApiConfiguration(
        baseUrl: _serverController.text,
      );
      final api =
          widget.apiFactory?.call(configuration) ??
          FidaCoreApi(configuration: configuration);

      _api?.close();
      _api = api;

      final challenge = await api.requestPhoneLogin(phone);

      if (!mounted) return;

      if (!challenge.canVerify) {
        setState(() {
          _challenge = null;
          _errorMessage =
              'Verification is not available for this number. '
              'Confirm the account is registered on the Fida Ride backend.';
        });
        return;
      }

      setState(() {
        _challenge = challenge;
        _codeController.text = challenge.developmentCode ?? '';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final api = _api;
    final challengeId = _challenge?.challengeId;
    final code = _codeController.text.trim();

    if (api == null || challengeId == null) {
      setState(() {
        _errorMessage = 'Request a verification code first.';
      });
      return;
    }

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _errorMessage = 'Enter the 6-digit verification code.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      final session = await api.verifyPhoneLogin(
        challengeId: challengeId,
        code: code,
      );

      if (session.role != widget.expectedRole) {
        throw FidaApiException(
          message:
              'This account is registered as ${session.role.wireValue}, '
              'not ${widget.expectedRole.wireValue}.',
        );
      }

      if (!mounted) return;

      setState(() {
        _session = session;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _changeNumber() {
    _api?.close();
    _api = null;

    setState(() {
      _challenge = null;
      _codeController.clear();
      _errorMessage = null;
    });
  }

  void _signOut() {
    _api?.close();
    _api = null;

    setState(() {
      _session = null;
      _challenge = null;
      _codeController.clear();
      _errorMessage = null;
    });
  }

  String _friendlyError(Object error) {
    if (error is FidaApiException) {
      return error.message;
    }

    if (error is ArgumentError || error is FormatException) {
      return error.toString();
    }

    return 'Authentication failed. Check the API server and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return widget.authenticatedBuilder(context, session, _signOut);
    }

    final isDriver = widget.expectedRole == AuthRole.driver;
    final developmentCode = _challenge?.developmentCode;

    return Scaffold(
      appBar: AppBar(title: Text(widget.appName)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FidaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                isDriver ? 'Driver sign in' : 'Sign in to ride',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: FidaSpacing.xs),
              Text(
                'Use the phone number registered with Fida Taxi.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: FidaSpacing.xl),
              TextField(
                controller: _phoneController,
                enabled: !_hasChallenge && !_isBusy,
                keyboardType: TextInputType.phone,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+250788123456',
                  helperText: 'Use international E.164 format.',
                ),
              ),
              const SizedBox(height: FidaSpacing.md),
              TextField(
                controller: _serverController,
                enabled: !_hasChallenge && !_isBusy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API server (testing)',
                  hintText: 'https://api.example.com/api/v1',
                  helperText:
                      'For a physical phone, use an API address reachable '
                      'from the phone.',
                ),
              ),
              const SizedBox(height: FidaSpacing.lg),
              if (!_hasChallenge)
                FidaPrimaryButton(
                  label: 'Send code',
                  isLoading: _isBusy,
                  onPressed: _requestCode,
                )
              else ...<Widget>[
                TextField(
                  controller: _codeController,
                  enabled: !_isBusy,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    hintText: '000000',
                  ),
                ),
                if (developmentCode != null) ...<Widget>[
                  const SizedBox(height: FidaSpacing.sm),
                  Text(
                    'Development OTP: $developmentCode',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: FidaSpacing.lg),
                FidaPrimaryButton(
                  label: 'Verify and continue',
                  isLoading: _isBusy,
                  onPressed: _verifyCode,
                ),
                const SizedBox(height: FidaSpacing.sm),
                TextButton(
                  onPressed: _isBusy ? null : _changeNumber,
                  child: const Text('Use a different number or server'),
                ),
              ],
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: FidaSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(FidaSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(FidaRadius.md),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

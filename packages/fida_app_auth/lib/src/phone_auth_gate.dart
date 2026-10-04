import 'package:fida_api/fida_api.dart';
import 'package:fida_core/fida_core.dart';
import 'package:fida_design_system/fida_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef FidaCoreApiFactory =
    FidaCoreApi Function(FidaApiConfiguration configuration);

typedef AuthenticatedBuilder =
    Widget Function(
      BuildContext context,
      AuthSession session,
      FidaCoreApi api,
      VoidCallback signOut,
    );

enum _AuthMode { signIn, register }

final class PhoneAuthGate extends StatefulWidget {
  const PhoneAuthGate({
    required this.appName,
    required this.expectedRole,
    required this.authenticatedBuilder,
    this.apiFactory,
    this.initialBaseUrl = const String.fromEnvironment(
      'FIDA_API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3100/api/v1',
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
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _licensePlateController = TextEditingController();

  FidaCoreApi? _api;
  PhoneLoginChallenge? _challenge;
  AuthSession? _session;
  _AuthMode _mode = _AuthMode.signIn;
  VehicleType _vehicleType = VehicleType.taxi;
  String? _errorMessage;
  String? _noticeMessage;
  bool _isBusy = false;
  bool _showServerSettings = false;

  bool get _hasChallenge => _challenge?.challengeId != null;
  bool get _isRegistering => _mode == _AuthMode.register;
  bool get _isDriver => widget.expectedRole == AuthRole.driver;

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
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  FidaCoreApi _replaceApi() {
    final configuration = FidaApiConfiguration(
      baseUrl: _serverController.text,
    );
    final api =
        widget.apiFactory?.call(configuration) ??
        FidaCoreApi(configuration: configuration);
    _api?.close();
    _api = api;
    return api;
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
      _noticeMessage = null;
    });

    try {
      final api = _replaceApi();
      final challenge = await api.requestPhoneLogin(phone);
      if (!mounted) return;

      if (!challenge.canVerify) {
        setState(() {
          _challenge = null;
          _errorMessage = 'Verification is not available for this number.';
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

  Future<void> _registerAccount() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final licensePlate = _licensePlateController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your first and last name.';
      });
      return;
    }
    if (phone.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your phone number in international format.';
      });
      return;
    }
    if (_isDriver && licensePlate.isEmpty) {
      setState(() {
        _errorMessage = 'Enter the vehicle license plate.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      final api = _replaceApi();

      if (_isDriver) {
        await api.registerDriver(
          DriverRegistration(
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            email: email.isEmpty ? null : email,
            vehicleType: _vehicleType,
            licensePlate: licensePlate,
          ),
        );
      } else {
        await api.registerRider(
          RiderRegistration(
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            email: email.isEmpty ? null : email,
          ),
        );
      }

      final challenge = await api.requestPhoneLogin(phone);
      if (!mounted) return;

      setState(() {
        _mode = _AuthMode.signIn;
        _challenge = challenge;
        _codeController.text = challenge.developmentCode ?? '';
        _noticeMessage =
            '${_isDriver ? 'Driver' : 'Rider'} account created. Verify the phone number to continue.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        final message = _friendlyError(error);
        if (message.toLowerCase().contains('already registered')) {
          _mode = _AuthMode.signIn;
          _noticeMessage = 'This phone already has an account. Sign in instead.';
          _errorMessage = null;
        } else {
          _errorMessage = message;
        }
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
      _noticeMessage = null;
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
      final message = _friendlyError(error);
      final notRegistered = message.toLowerCase().contains(
        'account not registered',
      );
      setState(() {
        if (notRegistered) {
          _challenge = null;
          _codeController.clear();
          _mode = _AuthMode.register;
          _errorMessage = null;
          _noticeMessage =
              'No account exists for this phone number. Create the ${_isDriver ? 'driver' : 'rider'} account below.';
        } else {
          _errorMessage = message;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _switchMode() {
    setState(() {
      _mode = _isRegistering ? _AuthMode.signIn : _AuthMode.register;
      _challenge = null;
      _codeController.clear();
      _errorMessage = null;
      _noticeMessage = null;
    });
  }

  void _changeNumber() {
    _api?.close();
    _api = null;
    setState(() {
      _challenge = null;
      _codeController.clear();
      _errorMessage = null;
      _noticeMessage = null;
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
      _noticeMessage = null;
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

  String _vehicleTypeLabel(VehicleType type) {
    return switch (type) {
      VehicleType.taxi => 'Taxi',
      VehicleType.moto => 'Moto',
      VehicleType.premium => 'Premium',
      VehicleType.tukTuk => 'Tuk Tuk',
      VehicleType.ev => 'Electric vehicle',
      VehicleType.accessible => 'Accessible',
      VehicleType.other => 'Other',
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final api = _api;
    if (session != null && api != null) {
      return widget.authenticatedBuilder(context, session, api, _signOut);
    }

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
                _hasChallenge
                    ? 'Verify your phone'
                    : _isRegistering
                    ? (_isDriver ? 'Create driver account' : 'Create account')
                    : (_isDriver ? 'Driver sign in' : 'Sign in to ride'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: FidaSpacing.xs),
              Text(
                _hasChallenge
                    ? 'Enter the verification code sent to ${_phoneController.text.trim()}.'
                    : _isRegistering
                    ? 'Create your Fida Taxi ${_isDriver ? 'driver' : 'rider'} profile.'
                    : 'Use the phone number registered with Fida Taxi.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: FidaSpacing.xl),
              if (_isRegistering && !_hasChallenge) ...<Widget>[
                TextField(
                  controller: _firstNameController,
                  enabled: !_isBusy,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const <String>[AutofillHints.givenName],
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: FidaSpacing.md),
                TextField(
                  controller: _lastNameController,
                  enabled: !_isBusy,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const <String>[AutofillHints.familyName],
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
                const SizedBox(height: FidaSpacing.md),
                TextField(
                  controller: _emailController,
                  enabled: !_isBusy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                  ),
                ),
                const SizedBox(height: FidaSpacing.md),
              ],
              if (!_hasChallenge) ...<Widget>[
                TextField(
                  controller: _phoneController,
                  enabled: !_isBusy,
                  keyboardType: TextInputType.phone,
                  autofillHints: const <String>[AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+250788123456',
                    helperText: 'Use international E.164 format.',
                  ),
                ),
                if (_isRegistering && _isDriver) ...<Widget>[
                  const SizedBox(height: FidaSpacing.md),
                  DropdownButtonFormField<VehicleType>(
                    initialValue: _vehicleType,
                    decoration: const InputDecoration(labelText: 'Vehicle type'),
                    items: VehicleType.values
                        .map(
                          (type) => DropdownMenuItem<VehicleType>(
                            value: type,
                            child: Text(_vehicleTypeLabel(type)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _isBusy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _vehicleType = value;
                              });
                            }
                          },
                  ),
                  const SizedBox(height: FidaSpacing.md),
                  TextField(
                    controller: _licensePlateController,
                    enabled: !_isBusy,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'License plate',
                      hintText: 'RAB 123 C',
                    ),
                  ),
                ],
                const SizedBox(height: FidaSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _isBusy
                        ? null
                        : () {
                            setState(() {
                              _showServerSettings = !_showServerSettings;
                            });
                          },
                    child: Text(
                      _showServerSettings
                          ? 'Hide server settings'
                          : 'Server settings',
                    ),
                  ),
                ),
                if (_showServerSettings) ...<Widget>[
                  const SizedBox(height: FidaSpacing.xs),
                  TextField(
                    controller: _serverController,
                    enabled: !_isBusy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'API server',
                      helperText: 'Advanced testing setting.',
                    ),
                  ),
                ],
                const SizedBox(height: FidaSpacing.lg),
                FidaPrimaryButton(
                  label: _isRegistering
                      ? (_isDriver ? 'Create driver account' : 'Create account')
                      : 'Send code',
                  isLoading: _isBusy,
                  onPressed: _isRegistering ? _registerAccount : _requestCode,
                ),
                const SizedBox(height: FidaSpacing.sm),
                TextButton(
                  onPressed: _isBusy ? null : _switchMode,
                  child: Text(
                    _isRegistering
                        ? 'Already have an account? Sign in'
                        : _isDriver
                        ? 'New driver? Create an account'
                        : 'New to Fida Taxi? Create an account',
                  ),
                ),
              ] else ...<Widget>[
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
                  child: const Text('Use a different number'),
                ),
              ],
              if (_noticeMessage != null) ...<Widget>[
                const SizedBox(height: FidaSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(FidaSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(FidaRadius.md),
                  ),
                  child: Text(
                    _noticeMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
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

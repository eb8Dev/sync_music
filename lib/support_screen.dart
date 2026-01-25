import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/providers/user_provider.dart';
import 'package:sync_music/widgets/custom_button.dart';
import 'package:sync_music/widgets/glass_card.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _category = "Bug Report";
  bool _isSubmitting = false;

  final List<String> _categories = [
    "Bug Report",
    "Feature Request",
    "General Feedback",
    "Other"
  ];

  @override
  void initState() {
    super.initState();
    final socket = ref.read(socketProvider);
    
    // Listen for success
    socket.on("TICKET_SUBMITTED", _onSuccess);
    
    // Listen for error
    socket.on("TICKET_ERROR", _onError);
  }

  @override
  void dispose() {
    final socket = ref.read(socketProvider);
    socket.off("TICKET_SUBMITTED");
    socket.off("TICKET_ERROR");
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _onSuccess(data) {
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(data['message'] ?? "Ticket submitted!"),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context); // Close screen
  }

  void _onError(msg) {
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.toString()),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    FocusScope.of(context).unfocus();

    final user = ref.read(userProvider);
    final socket = ref.read(socketProvider);

    final ticket = {
      "userId": user.userId,
      "username": user.username,
      "category": _category,
      "subject": _subjectCtrl.text.trim(),
      "message": _messageCtrl.text.trim(),
      "appVersion": "1.0.0", // Hardcoded or fetch from package_info_plus
      "platform": Theme.of(context).platform.toString(),
    };

    socket.emit("SUBMIT_TICKET", ticket);
    
    // Timeout safety
    Future.delayed(const Duration(seconds: 10), () {
        if (mounted && _isSubmitting) {
            setState(() => _isSubmitting = false);
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Request timed out. Check connection."),
                backgroundColor: Colors.orange,
              ),
            );
        }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SUPPORT"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   const Text(
                    "How can we help?",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Fill out the form below and we'll check it out.",
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Category Dropdown
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _category,
                          dropdownColor: const Color(0xFF2C5364),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          items: _categories.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              _category = newValue!;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Subject Input
                  _buildTextField(
                    controller: _subjectCtrl,
                    label: "Subject",
                    icon: Icons.title,
                    validator: (v) => v!.isEmpty ? "Please enter a subject" : null,
                  ),
                  const SizedBox(height: 16),

                  // Message Input
                  _buildTextField(
                    controller: _messageCtrl,
                    label: "Message",
                    icon: Icons.message,
                    maxLines: 6,
                    validator: (v) => v!.isEmpty ? "Please enter your message" : null,
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  if (_isSubmitting)
                    const Center(child: CircularProgressIndicator())
                  else
                    CustomButton(
                      label: "Submit Ticket",
                      icon: Icons.send_rounded,
                      onPressed: _submit,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return GlassCard(
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(icon, color: Colors.white60),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}

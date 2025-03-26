import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'location_tracking_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  String _response = "";
  bool _isProcessing = false;
  String _imageUrl = "";

  // For animations
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // For text-to-speech
  final FlutterTts flutterTts = FlutterTts();

  // For speech-to-text
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    // Initialize TTS
    _initTts();

    // Initialize STT
    _initSpeech();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  Future<void> _initSpeech() async {
    bool available = await _speech.initialize();
    if (!available) {
      print("Speech recognition not available");
    }
  }

  Future<void> _speak(String text) async {
    await flutterTts.speak(text);
  }

  Future<void> _listen() async {
    if (!await _requestMicrophonePermission()) {
      return;
    }
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        await _speech.listen(
          onResult: _onSpeechResult,
          listenFor: Duration(seconds: 30),
          partialResults: true,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Speech recognition not available")),
        );
      }
    } else {
      setState(() => _isListening = false);
      await _speech.stop();
    }
  }

  void _onSpeechResult(result) {
    setState(() {
      _response = result.recognizedWords;
      if (result.finalResult) {
        _isListening = false;
        _analyzeImage(query: _response); // Send user query to the model
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    flutterTts.stop();
    super.dispose();
  }

  Future<void> upload() async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dkglul7cz/upload');

    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = 'uploood'
      ..files.add(await http.MultipartFile.fromPath('file', _image!.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);

      setState(() {
        _imageUrl = jsonMap['url'];
      });

      // After getting the image URL, insert it into the "images" table
    
    }
  }

  Future<void> _getImageFromCamera() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _animationController.reset();
        _animationController.forward();
        _response = "";
      });

      // Automatically analyze the image and provide a description
      _analyzeImage();
    }
  }

  Future<void> _getImageFromGallery() async {
    final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _animationController.reset();
        _animationController.forward();
        _response = "";
      });

      // Automatically analyze the image and provide a description
      _analyzeImage();
    }
  }

  Future<void> _analyzeImage({String? query}) async {
    if (_image == null) {
      _speak("Please take or select an image first");
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Upload the image to Cloudinary
      await upload();

      // Use the API to get the completion
      final response = await http.post(
        Uri.parse('https://api.thehive.ai/api/v3/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer T4L0n9mDcWPPlaXbPCZK23Xg4v0vY7gu',
        },
        body: jsonEncode({
          'model': 'meta-llama/llama-3.2-11b-vision-instruct',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': query ?? "Describe this image in 30 words."},
                {
                  'type': 'image_url',
                  'image_url': {'url': _imageUrl}
                }
              ]
            }
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final result = jsonResponse['choices'][0]['message']['content'];

        setState(() {
          _response = result;
          _isProcessing = false;
        });

        // Automatically read the response
        _speak(result);
      } else {
        setState(() {
          _response = "Error: ${response.statusCode} - ${response.body}";
          _isProcessing = false;
        });
        _speak("Sorry, there was an error processing your request.");
      }
    } catch (e) {
      setState(() {
        _response = "Error: $e";
        _isProcessing = false;
      });
      _speak("Sorry, there was an error processing your request.");
    }
    finally {
    // In the finally block, insert the image record into Supabase
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      final insertionResponse = await Supabase.instance.client.from('images').insert({
        'user_id': userId,
        'image_url': _imageUrl,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (insertionResponse.error != null) {
        print('Error inserting image record: ${insertionResponse.error!.message}');
      } else {
        print('Image record inserted successfully.');
      }
    }
  }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Sense AI',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.location_on),
            tooltip: 'Track Location',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LocationTrackingPage(),
                ),
              );
            },
         
      ),
        ],
      ),
      body: GestureDetector(
        onLongPressStart: (_) {
          // Stop TTS if it's speaking
          flutterTts.stop().then((_) {
            setState(() {
              _isHolding = true;
            });
            _listen(); // Start listening to the user's query
          });
        },
        onLongPressEnd: (_) {
          setState(() {
            _isHolding = false;
          });
          _speech.stop().then((_) {
            if (_response.isNotEmpty) {
              // Send the recognized query to the model
              _analyzeImage(query: _response);
            }
          });
        },
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Image container
                      GestureDetector(
                        onDoubleTap: _getImageFromCamera,
                        child: Container(
                          height: 300,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _image == null
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.camera_alt_outlined,
                                          size: 64,
                                          color: colorScheme.onSurfaceVariant
                                              .withOpacity(0.6),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Tap to capture image',
                                          style: textTheme.bodyLarge?.copyWith(
                                            color: colorScheme.onSurfaceVariant
                                                .withOpacity(0.6),
                                        ),
                                        ),
                                        Text(
                                          'Double tap for quick capture',
                                          style: textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant
                                                .withOpacity(0.4),
                                        ),
                                        )
                                      ],
                                    ),
                                  )
                                : FadeTransition(
                                    opacity: _fadeAnimation,
                                    child: Image.file(
                                      _image!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Image source buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _getImageFromCamera,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Camera'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: colorScheme.primaryContainer,
                                foregroundColor: colorScheme.onPrimaryContainer,
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _getImageFromGallery,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: colorScheme.secondaryContainer,
                                foregroundColor:
                                    colorScheme.onSecondaryContainer,
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Response section
                      if (_response.isNotEmpty) ...[
                        Text(
                          'Analysis Result:',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color:
                                colorScheme.secondaryContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _response,
                                style: textTheme.bodyLarge?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    onPressed: () => _speak(_response),
                                    icon: const Icon(Icons.volume_up),
                                    tooltip: 'Read aloud',
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          colorScheme.surfaceContainerHighest,
                                      foregroundColor: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Quick access buttons for blind users
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildAccessibilityButton(
                      icon: Icons.camera_alt,
                      label: 'Capture',
                      onPressed: _getImageFromCamera,
                      color: colorScheme.primary,
                    ),
                    _buildAccessibilityButton(
                      icon: _isListening ? Icons.mic_off : Icons.mic,
                      label: _isListening ? 'Stop' : 'Ask',
                      onPressed: _listen,
                      color: colorScheme.secondary,
                      isActive: _isListening,
                    ),
                    _buildAccessibilityButton(
                      icon: Icons.volume_up,
                      label: 'Repeat',
                      onPressed: () => _speak(_response.isEmpty
                          ? "No analysis yet. Please capture an image."
                          : _response),
                      color: colorScheme.error,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccessibilityButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
    bool isActive = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: isActive ? 12 : 4,
                spreadRadius: isActive ? 2 : 0,
              ),
            ],
          ),
          child: Material(
            color: isActive ? color : color.withOpacity(0.2),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                  icon,
                  size: 28,
                  color: isActive ? Colors.white : color,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}

Future<bool> _requestMicrophonePermission() async {
  var status = await Permission.microphone.request();
  return status.isGranted;
}
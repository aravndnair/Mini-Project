import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';

class LocationTrackingPage extends StatefulWidget {
  const LocationTrackingPage({Key? key}) : super(key: key);

  @override
  _LocationTrackingPageState createState() => _LocationTrackingPageState();
}

class _LocationTrackingPageState extends State<LocationTrackingPage> {
  bool isGuardian = false;
  String statusMessage = '';
  bool isTracking = false;

  @override
  void initState() {
    super.initState();
    // Automatically track location if not in guardian mode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isGuardian) {
        _trackBlindLocation();
      }
    });
  }

  /// Blind mode: Track and insert location into blind_locations table.
  Future<void> _trackBlindLocation() async {
    setState(() {
      isTracking = true;
      statusMessage = 'Requesting location permission...';
    });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        statusMessage = 'Location services are disabled. Please enable them.';
        isTracking = false;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          statusMessage = 'Location permissions are denied.';
          isTracking = false;
        });
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() {
        statusMessage = 'Location permissions are permanently denied.';
        isTracking = false;
      });
      return;
    }

    setState(() {
      statusMessage = 'Fetching location...';
    });

    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      final userId = Supabase.instance.client.auth.currentUser?.id;

      // Insert location into blind_locations table.
      await Supabase.instance.client.from('blind_locations').insert({
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
      });

      setState(() {
        statusMessage = 'Location tracked successfully!';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        isTracking = false;
      });
    }
  }

  /// Guardian mode: Retrieve the latest blind location and send email.
  Future<void> _sendLocationEmail() async {
    setState(() {
      isTracking = true;
      statusMessage = 'Fetching blind person location...';
    });

    try {
      // Get the blind person's latest location.
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final locationRes = await Supabase.instance.client
          .from('blind_locations')
          .select()
          .eq('user_id', userId)
          .order('timestamp', ascending: false)
          .limit(1)
          .maybeSingle();

      if (locationRes == null) {
        setState(() {
          statusMessage = 'No blind location data available.';
        });
        return;
      }

      // Assuming locationRes.data returns a Map with keys 'latitude' and 'longitude'.
      final locationData = locationRes as Map<String, dynamic>;
      final double latitude = locationData['latitude'];
      final double longitude = locationData['longitude'];

      // Retrieve guardian email from profiles table.
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('email')
          .eq('user_id', userId)
          .single();

      if (profileRes == null) {
        setState(() {
          statusMessage = 'Guardian email not found.';
        });
        return;
      }

      final profileData = profileRes as Map<String, dynamic>;
      final guardianEmail = profileData['email'];

      // Compose email content.
      final subject = 'Blind Person Latest Location';
      final body = 'The latest location is:\n'
          'Latitude: $latitude\n'
          'Longitude: $longitude';

      // Configure SMTP settings (using Gmail as an example).
      String username = 'seeing37ai@gmail.com';
      String password = 'bwxb xzhq vrgu yabq'; // Use an app-specific password for Gmail.

      final smtpServer = gmail(username, password);

      final message = Message()
        ..from = Address(username, 'Sense AI')
        ..recipients.add(guardianEmail)
        ..subject = subject
        ..text = body;

      // Send the email.
      final sendReport = await send(message, smtpServer);

      setState(() {
        statusMessage = 'Email sent to guardian successfully!';
      });
      print('Message sent: ' + sendReport.toString());
    } catch (e) {
      setState(() {
        statusMessage = 'Error sending email: $e';
      });
    } finally {
      setState(() {
        isTracking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Tracker'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Toggle between Guardian and Blind mode.
            SwitchListTile(
              title: const Text('I am a Guardian'),
              value: isGuardian,
              onChanged: (bool value) {
                setState(() {
                  isGuardian = value;
                  statusMessage = '';
                  // If switched to blind mode, automatically track location.
                  if (!isGuardian) {
                    _trackBlindLocation();
                  }
                });
              },
            ),
            const SizedBox(height: 20),
            // In Guardian mode, show a button to send location via email.
            if (isGuardian)
              ElevatedButton(
                onPressed: isTracking ? null : _sendLocationEmail,
                child: isTracking
                    ? const CircularProgressIndicator()
                    : const Text('Track the Blind person Location'),
              )
            else
              const Text('Automatically tracking your location...'),
            const SizedBox(height: 20),
            // Display status messages.
            Text(statusMessage),
          ],
        ),
      ),
    );
  }
}

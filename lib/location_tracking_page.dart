import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

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
    // Automatically track location if in blind mode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isGuardian) {
        _trackBlindLocation();
      }
    });
  }

  /// Blind person mode: Automatically track and send this device’s location to blind_locations.
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

    // Insert location data into the blind_locations table.
    await Supabase.instance.client
        .from('blind_locations')
        .insert({
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


  /// Guardian mode: Manually retrieve the blind person’s latest location from blind_locations.
  Future<void> _retrieveBlindLocation() async {
    setState(() {
      isTracking = true;
      statusMessage = 'Fetching blind person location...';
    });

    try {
  // Ensure the current user id is not null.
  final userId = Supabase.instance.client.auth.currentUser!.id;
  
  // Perform the query.
  final res = await Supabase.instance.client
      .from('blind_locations')
      .select()
      .eq('user_id', userId)
      .order('timestamp', ascending: false)
      .limit(1)
      .maybeSingle();
  
  // If the response is a Map, we try to extract error and data.
  if (res is Map<String, dynamic>) {
    // Check if the Map contains an 'error' key.
    if (res.containsKey('error') && res['error'] != null) {
      setState(() {
        statusMessage = 'Error fetching location: ${res['error']['message']}';
      });
    }
    // Otherwise, check if it contains a 'data' key.
    else if (res.containsKey('data') && res['data'] != null) {
      final data = res['data'] as Map<String, dynamic>;
      setState(() {
        statusMessage =
            'Blind Location: Lat ${data['latitude']}, Lon ${data['longitude']}';
      });
    } else {
      setState(() {
        statusMessage = 'No blind location data available.';
      });
    }
  } 
  // If res isn't a Map, assume it is the data directly.
  else if (res != null) {
    final data = res as Map<String, dynamic>;
    setState(() {
      statusMessage =
          'Blind Location: Lat ${data['latitude']}, Lon ${data['longitude']}';
    });
  } else {
    setState(() {
      statusMessage = 'No blind location data available.';
    });
  }
} catch (e) {
  setState(() {
    statusMessage = 'Error: $e';
  });
}
 finally {
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
            // Toggle: Guardian mode when enabled; Blind mode when disabled.
            SwitchListTile(
              title: const Text('I am a Guardian'),
              value: isGuardian,
              onChanged: (bool value) {
                setState(() {
                  isGuardian = value;
                  statusMessage = '';
                  // If switched to blind mode, immediately track location.
                  if (!isGuardian) {
                    _trackBlindLocation();
                  }
                });
              },
            ),
            const SizedBox(height: 20),
            // In Guardian mode, display a manual "Retrieve" button.
            if (isGuardian)
              ElevatedButton(
                onPressed: isTracking ? null : _retrieveBlindLocation,
                child: isTracking
                    ? const CircularProgressIndicator()
                    : const Text('Retrieve Blind Person Location'),
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

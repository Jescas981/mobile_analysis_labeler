# Mobile Analysis

A Flutter application for real-time mobile sensor data analysis, recording, and labeling via MQTT.

## Features

- **Real-time MQTT Subscription**: Connects to an MQTT broker (default: `127.0.0.1:1883`) and subscribes to:
  - `/mobile/imu`: Acceleration and Gyroscope data.
  - `/mobile/gps`: Latitude and Longitude data.
- **Live Visualization**:
  - **Acceleration Chart**: Real-time display of X, Y, and Z acceleration.
  - **Gyroscope Chart**: Real-time display of X, Y, and Z angular velocity.
  - **Map View**: Interactive OpenStreetMap tracking the current GPS location and recording path.
- **Data Labeling**:
  - Assign custom labels (e.g., "Walking", "Running", "Still") to time-series data.
  - "Hold to Label" functionality for precise windowing of activities.
  - Visual feedback of labeled intervals on the charts.
- **Data Recording**:
  - Export recorded sessions to CSV format.
  - Files are saved to the application's documents directory with timestamps and labels.

## Getting Started

### Prerequisites

- A running MQTT broker (e.g., Mosquitto).
- Flutter SDK installed.

### Installation

1. Clone the repository.
2. Run `flutter pub get` to install dependencies.
3. Start the application with `flutter run`.

### Usage

1. **Connect**: The app attempts to connect to the broker at `127.0.0.1` by default. Use the cloud icon in the AppBar to reconnect if needed.
2. **Record**: Press the **RECORD** button to start capturing incoming MQTT data.
3. **Label**: While recording, enter a label name and **HOLD** the label button during the specific activity.
4. **Save**: Press **STOP** to finish the session and save the data to a CSV file.

## Data Format

The application expects JSON payloads on the following topics:

### `/mobile/imu`
```json
{
  "timestamp": 1678901234567,
  "session": "user_123",
  "acc": { "x": 0.1, "y": 9.8, "z": 0.5 },
  "gyro": { "x": 0.01, "y": 0.02, "z": 0.03 }
}
```

### `/mobile/gps`
```json
{
  "timestamp": 1678901234567,
  "session": "user_123",
  "gps": { "lat": 45.123, "lon": 9.456 }
}
```

## Dependencies

- `mqtt_client`: MQTT connectivity.
- `fl_chart`: Real-time data visualization.
- `flutter_map`: Interactive map integration.
- `path_provider`: Local file storage for CSV exports.

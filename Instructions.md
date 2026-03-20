I want to make an application which subscribe to these topics:
/mobile/imu
/mobile/gps

```
      if (topic === config.mqtt.topics.imu) {
            const doc = {
                timestamp: timestamp,
                session: payload.session,
                ax: payload.acc.x,
                ay: payload.acc.y,
                az: payload.acc.z,
                gx: payload.gyro ? payload.gyro.x : 0.0,
                gy: payload.gyro ? payload.gyro.y : 0.0,
                gz: payload.gyro ? payload.gyro.z : 0.0,
                received_at: received_at,
            };
            const result = await imuCollection.insertOne(doc);
            console.log(`[MQTT] IMU data saved: session=${payload.session}, id=${result.insertedId}`);
            
            // CSV recording
            csvWriter.append('imu', payload.session, doc);

        } else if (topic === config.mqtt.topics.gps) {
            const doc = {
                timestamp: timestamp,
                session: payload.session,
                lat: payload.gps.lat,
                lon: payload.gps.lon,
                received_at: received_at,
            };
            
        }

```

I want to subscribe to these topics and be able to label time series:
It consists in two buttons:
Button Record/Stop: It only saves data of these documents
Button Label: It assigns labels to a time window while the button is pressed, when released it stops
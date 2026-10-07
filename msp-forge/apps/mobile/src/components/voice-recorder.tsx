// Records a voice note offline with expo-audio (SDK 57). The caller seals and
// stores it. Recording needs the voice recording consent (POPIA purpose chip).

import { RecordingPresets, requestRecordingPermissionsAsync, setAudioModeAsync, useAudioRecorder, useAudioRecorderState } from 'expo-audio';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { formatDuration } from '@/lib/dates';
import { space } from '@/theme/tokens';

import { Button, Notice, Txt } from './ui';

export function VoiceRecorder({ consentGiven, onRecorded, label = 'Record a voice note' }: { consentGiven: boolean; onRecorded: (uri: string, seconds: number) => Promise<void> | void; label?: string }) {
  const recorder = useAudioRecorder(RecordingPresets.HIGH_QUALITY);
  const state = useAudioRecorderState(recorder, 250);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  if (!consentGiven) {
    return <Notice tone="warning" title="Voice notes are off">Give the voice recording consent under Account, POPIA consents, to record voice notes.</Notice>;
  }

  const start = async () => {
    setError(null);
    try {
      const perm = await requestRecordingPermissionsAsync();
      if (!perm.granted) {
        setError('Allow the microphone for Bee-Inspect in your phone settings to record voice notes.');
        return;
      }
      await setAudioModeAsync({ allowsRecording: true, playsInSilentMode: true });
      await recorder.prepareToRecordAsync();
      recorder.record();
    } catch {
      setError('Recording could not start on this device.');
    }
  };

  const stop = async () => {
    const seconds = Math.max(1, Math.round((state.durationMillis ?? 0) / 1000));
    try {
      setSaving(true);
      await recorder.stop();
      await setAudioModeAsync({ allowsRecording: false, playsInSilentMode: true });
      if (recorder.uri) await onRecorded(recorder.uri, seconds);
      else setError('The recording was empty. Try again.');
    } catch {
      setError('The recording could not be saved.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <View style={styles.wrap}>
      {state.isRecording ? (
        <View style={styles.row}>
          <Txt variant="bodyStrong" accessibilityRole="alert">
            Recording {formatDuration((state.durationMillis ?? 0) / 1000)}
          </Txt>
          <Button title="Stop and keep" icon="stop" kind="danger" compact onPress={stop} />
        </View>
      ) : (
        <Button title={label} icon="microphone-outline" kind="secondary" busy={saving} onPress={start} />
      )}
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: space.sm },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: space.sm },
});

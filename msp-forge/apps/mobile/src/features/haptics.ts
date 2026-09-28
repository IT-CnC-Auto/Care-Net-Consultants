// Haptic feedback where it helps a person on site: a light tap on a choice, a
// success buzz when something is saved, a warning when a rule stops them.
// Silent on the web preview and wherever the phone has no haptics.

import * as Haptics from 'expo-haptics';
import { Platform } from 'react-native';

const on = Platform.OS === 'ios' || Platform.OS === 'android';

export const haptic = {
  tap(): void {
    if (on) void Haptics.selectionAsync().catch(() => {});
  },
  success(): void {
    if (on) void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
  },
  warn(): void {
    if (on) void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {});
  },
};
